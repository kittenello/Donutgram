import copy
import base64
import hashlib
import importlib.util
import io
import json
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

SDK = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dgplugin", SDK / "tools/dgplugin.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

class SDKTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.manifest = json.loads((SDK / "examples/quiet-links/manifest.json").read_text(encoding="utf-8-sig"))

    def tearDown(self):
        self.temp.cleanup()

    def single(self, content, name="test.donut.js"):
        target = self.directory / name
        target.write_text(content, encoding="utf-8")
        return target

    def zip(self, files, name="test.dgplugin"):
        target = self.directory / name
        with zipfile.ZipFile(target, "w") as archive:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                for key, value in files:
                    archive.writestr(key, value)
        return target

    def base_files(self):
        return [("manifest.json", json.dumps(self.manifest)), ("main.js", 'const _plugin = "donutgram"; definePlugin({activate(){}});')]

    def test_examples_and_mock_host(self):
        for name in ["quiet-links", "templates", "selected-text", "public-repository", "native-controls", "profile-empty", "unread-first"]:
            with self.subTest(example=name):
                metadata, files = tool.read_package(SDK / "examples" / name)
                self.assertGreater(len(files), 0)
                capability = "ui.transform" if name in {"profile-empty", "unread-first"} else "ui.contribute"
                self.assertTrue(any(permission["capability"] == capability for permission in metadata["permissions"]))
                result = tool.mock_test(SDK / "examples" / name, SDK / "tests" / (name + ".json"))
                self.assertTrue(result["passed"])

    def page(self, nodes=None):
        return {"id": "page", "title": "page", "nodes": nodes or [{"type": "text", "id": "text", "text": "safe"}]}

    def test_native_controls_callbacks_preserve_schema_values(self):
        result = tool.mock_test(SDK / "examples/native-controls", SDK / "tests/native-controls.json")
        page = result["pages"][0]
        self.assertEqual(tool.ui_page(page), page)
        self.assertEqual({node["type"] for node in page["nodes"]}, {"markdown", "section", "list", "button", "image"})
        controls = next(node for node in page["nodes"] if node["id"] == "controls")["children"]
        self.assertEqual({node["type"] for node in controls}, {"toggle", "input", "multiline", "slider", "stepper", "select"})

    def test_public_repository_is_data_only_and_handles_unavailability(self):
        source = SDK / "examples/public-repository"
        result = tool.mock_test(source, SDK / "tests/public-repository.json")
        self.assertEqual(result["networkCalls"], [{"url": "https://api.github.com/repos/madler/zlib", "method": "GET"}])
        self.assertEqual(result["draft"], None)
        fixture = {"commands": ["repository-summary"], "unavailable": ["network.request"], "expectedNetworkCalls": [], "expectedPages": [], "expectedToasts": ["публичная сеть недоступна в этой сборке"]}
        target = self.directory / "unavailable.json"
        target.write_text(json.dumps(fixture), encoding="utf-8")
        self.assertTrue(tool.mock_test(source, target)["passed"])

    def test_public_network_mock_denies_undeclared_origin(self):
        source = self.directory / "network"
        source.mkdir()
        example = SDK / "examples/public-repository"
        (source / "manifest.json").write_bytes((example / "manifest.json").read_bytes())
        (source / "main.js").write_text((example / "main.js").read_text(encoding="utf-8").replace("https://api.github.com/repos/madler/zlib", "https://example.org/private"), encoding="utf-8")
        with self.assertRaises(tool.ValidationError):
            tool.mock_test(source, SDK / "tests/public-repository.json")

    def test_transform_examples_keep_pinned_handles_and_live_panes(self):
        profile = tool.mock_test(SDK / "examples/profile-empty", SDK / "tests/profile-empty.json")
        self.assertEqual(profile["transforms"], ["hide-empty-panes"])
        sort = tool.mock_test(SDK / "examples/unread-first", SDK / "tests/unread-first.json")
        self.assertEqual(sort["transforms"], ["unread-first"])
        fixture = json.loads((SDK / "tests/unread-first.json").read_text())
        fixture["settings"]["hideRead"] = False
        fixture["transforms"][0]["expectedPatch"]["hidden"] = []
        target = self.directory / "no-filter.json"
        target.write_text(json.dumps(fixture), encoding="utf-8")
        self.assertTrue(tool.mock_test(SDK / "examples/unread-first", target)["passed"])

    def test_optional_private_scope_cannot_enter_network_profile(self):
        metadata = json.loads((SDK / "examples/public-repository/manifest.json").read_text())
        metadata["optionalPermissions"] = [{"capability": "ui.transform", "scope": "chatList", "reason": "sort"}]
        with self.assertRaises(tool.ValidationError):
            tool.manifest(metadata)

    def test_native_bootstrap_adapter_methods_send_exact_parameters(self):
        target = self.directory / "native-adapters"
        target.mkdir()
        permissions = [{"capability": "ui.contribute", "scope": "settings", "reason": "command"}]
        for capability in ["messages.read", "chats.metadata.read", "peers.read", "files.userSelected", "messages.compose", "messages.sendInteractive", "translation.request", "navigation.open"]:
            permissions.append({"capability": capability, "scope": tool.SCOPES[capability][0], "reason": "explicit fixture operation"})
        metadata = {"kind": "donutgram.plugin", "schemaVersion": 1, "id": "dev.example.native-fixture", "name": "native fixture", "version": "1.0.0", "description": "reviewed mock adapter calls", "apiVersion": "^1.0.0", "permissions": permissions}
        (target / "manifest.json").write_text(json.dumps(metadata), encoding="utf-8")
        (target / "main.js").write_text('const _plugin="donutgram"; export default definePlugin({async activate(api){await api.commands.register({id:"test",title:"test",placement:"settings",async run(){await api.messages.read();await api.chats.metadata();await api.peers.read();const file=await api.files.pick();await api.files.read({handle:file.handle});const prepared=await api.actions.messages.prepare({text:"shown text"});await api.actions.messages.sendInteractive({handle:prepared.handle});await api.actions.messages.compose({text:"draft"});await api.translation.request({targetLanguage:"ru"});await api.navigation.open({screen:"plugins"});}})}});', encoding="utf-8")
        methods = [("messages.read", {}), ("chats.metadata", {}), ("peers.read", {}), ("files.pick", {}), ("files.read", {"handle": "file.1"}), ("messages.prepare", {"text": "shown text"}), ("messages.sendInteractive", {"handle": "preview.1"}), ("messages.compose", {"text": "draft"}), ("translation.request", {"targetLanguage": "ru"}), ("navigation.open", {"screen": "plugins"})]
        results = {method: None for method, _ in methods}
        results["files.pick"] = {"handle": "file.1", "name": "selected.txt", "size": 1}
        results["messages.prepare"] = {"handle": "preview.1", "recipient": "opaque", "text": "shown text", "expiresIn": 45}
        fixture = {"commands": ["test"], "nativeResults": results, "expectedNativeCalls": [{"method": method, "params": params} for method, params in methods]}
        fixture_path = self.directory / "native-fixture.json"
        fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
        self.assertTrue(tool.mock_test(target, fixture_path)["passed"])

    def test_ui_rejects_unknown_fields_wrong_node_shape_and_unsafe_assets(self):
        invalid = [
            {"type": "html", "id": "bad"},
            {"type": "text", "id": "bad", "url": "https://example.org"},
            {"type": "text", "id": "bad", "callbackId": "callback.1"},
            {"type": "button", "id": "bad"},
            {"type": "toggle", "id": "bad", "value": 1, "callbackId": "callback.1"},
            {"type": "input", "id": "bad", "value": [], "callbackId": "callback.1"},
            {"type": "text", "id": "bad", "children": []},
            {"type": "image", "id": "bad", "asset": "https://example.org/a.png"},
            {"type": "image", "id": "bad", "asset": "assets/icon.png"},
            {"type": "text", "id": "bad", "asset": "asset.1"},
            {"type": "text", "id": "bad", "minimum": 0},
        ]
        for node in invalid:
            with self.subTest(node=node), self.assertRaises(tool.ValidationError):
                tool.ui_page(self.page([node]))

    def test_ui_numeric_bounds_alignment_and_scalar_selects(self):
        base = {"type": "slider", "id": "level", "minimum": -1, "maximum": 1, "step": 0.1, "value": 0.3, "callbackId": "callback.1"}
        tool.ui_page(self.page([base]))
        for changes in [{"maximum": -1}, {"step": 0}, {"step": 3}, {"step": 1e-9}, {"value": 0.35}, {"value": 2}, {"minimum": -1e10}, {"value": True}, {"value": float("inf")}]:
            with self.subTest(changes=changes), self.assertRaises(tool.ValidationError):
                tool.ui_page(self.page([{**base, **changes}]))
        select = {"type": "select", "id": "choice", "callbackId": "callback.2", "options": [{"title": "none", "value": None}, {"title": "number", "value": 1}]}
        tool.ui_page(self.page([select]))
        tool.ui_page(self.page([{**select, "value": 1.0}]))
        for changes in [{"value": True}, {"value": "1"}, {"options": []}, {"options": [{"title": "bad", "value": {"a": 1}}]}]:
            with self.subTest(changes=changes), self.assertRaises(tool.ValidationError):
                tool.ui_page(self.page([{**select, **changes}]))

    def test_ui_total_depth_uniqueness_utf16_and_encoded_limits(self):
        tool.ui_page(self.page([{"type": "text", "id": "n" + str(index)} for index in range(128)]))
        with self.assertRaises(tool.ValidationError):
            tool.ui_page(self.page([{"type": "text", "id": "n" + str(index)} for index in range(129)]))
        leaf = {"type": "text", "id": "leaf"}
        for depth in range(6):
            leaf = {"type": "section", "id": "section" + str(depth), "children": [leaf]}
        tool.ui_page(self.page([leaf]))
        with self.assertRaises(tool.ValidationError):
            tool.ui_page(self.page([{"type": "section", "id": "too-deep", "children": [leaf]}]))
        with self.assertRaises(tool.ValidationError):
            tool.ui_page(self.page([{"type": "section", "id": "same", "children": [{"type": "text", "id": "same"}]}]))
        tool.ui_page({**self.page(), "title": "😀" * 100})
        with self.assertRaises(tool.ValidationError):
            tool.ui_page({**self.page(), "title": "😀" * 101})
        for title in ["bad\nline", "bad\u202ename", "bad\u0000name"]:
            with self.assertRaises(tool.ValidationError):
                tool.ui_page({**self.page(), "title": title})
        with self.assertRaises(tool.ValidationError):
            tool.ui_page(self.page([{"type": "text", "id": "long", "text": "😀" * 2049}]))
        with self.assertRaises(tool.ValidationError):
            tool.ui_page(self.page([{"type": "text", "id": "long" + str(index), "text": "a" * 4096} for index in range(17)]))

    def test_validate_ui_cli_and_schema_declare_native_constraints(self):
        target = self.directory / "page.json"
        target.write_text(json.dumps(self.page()), encoding="utf-8")
        result = subprocess.run([sys.executable, str(SDK / "tools/dgplugin.py"), "validate-ui", str(target)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["nativeValidationRequired"])
        schema = json.loads((SDK / "schemas/ui.schema.json").read_text())
        self.assertEqual(set(schema["$defs"]["node"]["properties"]["type"]["enum"]), tool.UI_TYPES)
        self.assertEqual(schema["properties"]["title"]["maxLength"], 200)
        self.assertEqual(schema["x-nativeConstraints"]["maximumTotalNodes"], 128)
        self.assertEqual(schema["x-nativeConstraints"]["maximumNodeDepth"], 6)

    def test_shared_native_page_validation_fixture_contract(self):
        fixtures = json.loads((SDK / "tests/ui-validation-cases.json").read_text())
        for fixture in fixtures:
            with self.subTest(case=fixture["name"]):
                if fixture["valid"]:
                    self.assertEqual(tool.ui_page(fixture["page"]), fixture["page"])
                else:
                    with self.assertRaises(tool.ValidationError):
                        tool.ui_page(fixture["page"])

    def test_compatibility_reports_advisory_availability_and_no_signature_attestation(self):
        package = self.zip(self.base_files() + [("signature.json", '{"algorithm":"Ed25519","publicKey":"unverified","signature":"unverified"}')])
        result = subprocess.run([sys.executable, str(SDK / "tools/dgplugin.py"), "compatibility", str(package)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["signatureVerification"], "native_installer_required")
        self.assertTrue(report["requiresRuntimeAvailabilityCheck"])
        self.assertNotIn("availableCapabilities", report)
        self.assertEqual(report["availabilitySource"], "native capabilities.list at runtime")

    def test_cross_tool_canonical_bytes_match_published_vectors(self):
        module_spec = importlib.util.spec_from_file_location("signature_fixture", SDK / "tools/signature_fixture.py")
        reference = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(reference)
        fixture = json.loads((SDK / "tests/signature-canonical-v1.json").read_text(encoding="utf-8"))
        for vector in fixture["vectors"]:
            encoded = reference.canonical(vector["value"])
            self.assertEqual(encoded, base64.b64decode(vector["base64"]))
            self.assertEqual(hashlib.sha256(encoded).hexdigest(), vector["sha256"])
        for invalid in [float("nan"), float("inf")]:
            with self.assertRaises(ValueError):
                reference.canonical(invalid)

    def test_mock_rejects_unproduced_events_and_unattached_display_links(self):
        target = self.directory / "reserved"
        target.mkdir()
        metadata = {**self.manifest, "id": "dev.example.reserved", "permissions": [{"capability": "ui.contribute", "scope": "settings", "reason": "report fixture results"}, {"capability": "ui.transform", "scope": "displayLinks", "reason": "reserved fixture only"}]}
        (target / "manifest.json").write_text(json.dumps(metadata), encoding="utf-8")
        (target / "main.js").write_text('const _plugin="donutgram"; definePlugin({async activate(api){for(const name of ["plugin.activated","account.contextChanged","app.foreground","theme.changed","locale.changed","chat.opened","chat.closed","composer.changed","message.observed"]) await (await api.events.on(name,()=>{})).dispose(); for(const name of ["app.background","powerSaving.changed","plugin.deactivating","message.edited","message.deleted","selection.changed","network.reachabilityChanged"]){try{await api.events.on(name,()=>{});throw Error("accepted unsupported event")}catch(e){if(e.code!=="feature_unavailable") throw e}}try{await api.transforms.register({id:"reserved",slot:"displayLinks"},()=>({labels:[]}));throw Error("accepted unavailable transform")}catch(e){if(e.code!=="feature_unavailable") throw e}await api.ui.toast("unavailable contracts rejected")}});', encoding="utf-8")
        fixture = self.directory / "reserved.json"
        fixture.write_text(json.dumps({"expectedToasts": ["unavailable contracts rejected"]}), encoding="utf-8")
        self.assertTrue(tool.mock_test(target, fixture)["passed"])

    def test_create_and_deterministic_pack(self):
        directory = self.directory / "generated"
        tool.create(directory, "dev.example.generated")
        first, second = self.directory / "a.dgplugin", self.directory / "b.dgplugin"
        tool.pack(directory, first)
        tool.pack(directory, second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertEqual(tool.read_package(first)[0]["id"], "dev.example.generated")
        with self.assertRaises(tool.ValidationError):
            tool.create(directory, "dev.example.generated")

    def test_quiet_links_preserves_nontracking_query_bytes(self):
        text = "https://example.test/?%75tm_source=x&ok=%ZZ&%ZZ=x#fragment"
        fixture = {"draft": {"handle": "draft", "revision": "r1", "text": text, "selection": {"start": 0, "end": len(text)}}, "commands": ["clean-selected-link"], "expectedText": "https://example.test/?ok=%ZZ&%ZZ=x#fragment"}
        fixture_path = self.directory / "query.json"
        fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
        self.assertTrue(tool.mock_test(SDK / "examples/quiet-links", fixture_path)["passed"])

    def test_preview_never_runs_body(self):
        text = 'const _plugin = "donutgram"; const manifest = ' + json.dumps(self.manifest) + '; throw new Error("must not execute");'
        metadata, files = tool.read_package(self.single(text))
        self.assertEqual(metadata["id"], self.manifest["id"])

    def test_expressions_getters_spread_and_duplicates_rejected(self):
        invalid = ['{"kind": getKind()}', '{get kind(){return "donutgram.plugin"}}', '{...other}', '{"kind":"a","kind":"b"}', '{"__proto__":{}}', '{"constructor":{}}']
        for literal in invalid:
            with self.subTest(literal=literal), self.assertRaises(tool.ValidationError):
                tool.read_package(self.single('const _plugin = "donutgram"; const manifest = ' + literal + ';'))

    def test_ordinary_javascript_is_not_plugin(self):
        with self.assertRaises(tool.ValidationError):
            tool.read_package(self.single("throw 1;", "plain.js"))
        with self.assertRaises(tool.ValidationError):
            tool.read_package(self.single('const _plugin = "other";'))

    def test_profile_and_permission_denial(self):
        value = copy.deepcopy(self.manifest)
        value["permissions"].append({"capability": "network.public", "scope": "declaredOrigins", "reason": "network", "origins": ["https://example.com"]})
        with self.assertRaises(tool.ValidationError):
            tool.manifest(value)
        value["profile"] = "publicNetwork"
        with self.assertRaises(tool.ValidationError):
            tool.manifest(value)
        value = copy.deepcopy(self.manifest)
        value["permissions"].append(value["permissions"][0])
        with self.assertRaises(tool.ValidationError):
            tool.manifest(value)
        value = copy.deepcopy(self.manifest)
        value["permissions"][0]["capability"] = "account.logout"
        with self.assertRaises(tool.ValidationError):
            tool.manifest(value)

    def test_runtime_size_and_case_bounds(self):
        for extra in [[("large.js", "x" * (1024 * 1024 + 1))], [("MAIN.js", "a")], [(f"modules/{index}.js", "a") for index in range(128)]]:
            with self.subTest(extra=extra[0][0]), self.assertRaises(tool.ValidationError):
                tool.read_package(self.zip(self.base_files() + extra))

    def test_traversal_links_duplicates_and_nested_archives(self):
        for name in ["../escape.js", "/escape.js", "assets/b.zip", "main.js"]:
            with self.subTest(name=name), self.assertRaises(tool.ValidationError):
                tool.read_package(self.zip(self.base_files() + [(name, "test")]))
        with self.assertRaises(tool.ValidationError):
            tool.safe_path("a\\b.js")
        symlink = zipfile.ZipInfo("link.js")
        symlink.create_system = 3
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(tool.ValidationError):
            tool.read_package(self.zip(self.base_files() + [(symlink, "main.js")]))

    def test_local_header_mismatch(self):
        target = self.zip(self.base_files())
        data = bytearray(target.read_bytes())
        struct.pack_into("<I", data, 18, 1)
        target.write_bytes(data)
        with self.assertRaises(tool.ValidationError):
            tool.read_package(target)

    def test_cli_error_is_json(self):
        target = self.single('const _plugin = "donutgram"; const manifest = {"x": alert(1)};')
        result = subprocess.run([sys.executable, str(SDK / "tools/dgplugin.py"), "validate", str(target)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", json.loads(result.stderr))
        self.assertNotIn("Traceback", result.stderr)

    def test_deep_json_rejected(self):
        with self.assertRaises(tool.ValidationError):
            tool.decode_json("[" * 30 + "0" + "]" * 30)

if __name__ == "__main__":
    unittest.main()
