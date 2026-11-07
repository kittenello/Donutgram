import copy
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
        for name in ["quiet-links", "templates", "selected-text"]:
            with self.subTest(example=name):
                metadata, files = tool.read_package(SDK / "examples" / name)
                self.assertGreater(len(files), 0)
                self.assertTrue(any(permission["capability"] == "ui.contribute" for permission in metadata["permissions"]))
                result = tool.mock_test(SDK / "examples" / name, SDK / "tests" / (name + ".json"))
                self.assertTrue(result["passed"])

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
