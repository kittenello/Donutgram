import argparse
import hashlib
import io
import json
import math
import re
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SCOPES = {
    "ui.contribute": ["settings", "composer", "selection", "messageMenu", "chatToolbar"],
    "ui.transform": ["profile", "chatList", "displayLinks"],
    "theme.read": ["currentTheme"], "theme.contribute": ["localTokens"],
    "composer.read": ["activeComposer"], "composer.transform": ["activeComposer"],
    "messages.selection.read": ["activeSelection"], "messages.read": ["selectedChats"],
    "chats.metadata.read": ["selectedChats"], "peers.read": ["selectedPeers"],
    "storage.local": ["pluginAccount"], "network.public": ["declaredOrigins"],
    "translation.request": ["selectedText"], "navigation.open": ["safeScreens"],
    "notifications.local": ["pluginAccount"], "files.userSelected": ["selectedFile"],
    "messages.compose": ["chosenRecipient"], "messages.sendInteractive": ["chosenRecipient"]
}
PRIVATE = {"composer.read", "composer.transform", "messages.selection.read", "messages.read", "chats.metadata.read", "peers.read", "files.userSelected", "messages.compose", "messages.sendInteractive", "translation.request", "ui.transform"}
FIELDS = {"kind", "schemaVersion", "id", "name", "version", "description", "author", "apiVersion", "minClientVersion", "entry", "icon", "permissions", "optionalPermissions", "settingsSchema", "profile", "changelog"}
AVAILABLE = ["commands", "events", "storage", "settings", "capabilities", "environment", "composer", "selection", "theme", "ui.toast"]

class ValidationError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise ValidationError(message)

def pairs(values):
    result = {}
    for key, value in values:
        require(key not in result and key not in {"__proto__", "prototype", "constructor"}, "duplicate or reserved json key")
        result[key] = value
    return result

def check_tree(value, depth=0, count=None):
    count = count if count is not None else [0]
    count[0] += 1
    require(depth <= 24 and count[0] <= 8192, "json complexity limit")
    if isinstance(value, str):
        require("\0" not in value and len(value.encode("utf-8")) <= 16384, "invalid or oversized string")
    elif isinstance(value, float):
        require(math.isfinite(value), "nonfinite json number")
    elif isinstance(value, dict):
        for key, item in value.items():
            check_tree(key, depth + 1, count)
            check_tree(item, depth + 1, count)
    elif isinstance(value, list):
        for item in value:
            check_tree(item, depth + 1, count)

def decode_json(text, partial=False):
    decoder = json.JSONDecoder(object_pairs_hook=pairs, parse_constant=lambda value: (_ for _ in ()).throw(ValidationError("invalid json constant")))
    try:
        value, end = decoder.raw_decode(text.lstrip())
    except (ValueError, RecursionError) as error:
        raise ValidationError(str(error)) from error
    check_tree(value)
    consumed = len(text) - len(text.lstrip()) + end
    require(partial or not text[consumed:].strip(), "trailing json content")
    return value, consumed

def token(text, offset, literal):
    while offset < len(text) and text[offset] in " \t\r\n":
        offset += 1
    require(text.startswith(literal, offset), "invalid static plugin header")
    return offset + len(literal)

def marker(text):
    offset = 0
    for literal in ["const", "_plugin", "=", '"donutgram"', ";"]:
        offset = token(text, offset, literal)
    return offset

def single_manifest(text):
    offset = marker(text)
    for literal in ["const", "manifest", "="]:
        offset = token(text, offset, literal)
    value, consumed = decode_json(text[offset:], partial=True)
    offset = token(text, offset + consumed, ";")
    require(len(text[:offset].encode("utf-8")) <= 131072, "manifest limit")
    return value

def safe_path(name):
    require(isinstance(name, str) and 0 < len(name.encode("utf-8")) <= 240, "invalid package path")
    require(name == unicodedata.normalize("NFC", name) and not name.startswith("/") and not any(char in name for char in "\\:%"), "invalid package path")
    parts = name.split("/")
    require(len(parts) <= 8 and all(part and part not in {".", ".."} and not part.endswith((".", " ")) for part in parts), "invalid package path")
    require(not any(ord(char) < 32 or ord(char) == 127 or 0x202a <= ord(char) <= 0x202e or 0x2066 <= ord(char) <= 0x2069 for char in name), "invalid path characters")
    return name

def semver(value):
    require(isinstance(value, str) and len(value) <= 64 and re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", value), "invalid semver")
    prerelease = value.split("+", 1)[0].partition("-")[2]
    require(not any(part.isdigit() and len(part) > 1 and part.startswith("0") for part in prerelease.split(".")), "invalid semver prerelease")

def string(value, maximum, minimum=0):
    require(isinstance(value, str) and minimum <= len(value) <= maximum, "invalid text field")

def manifest(value):
    require(isinstance(value, dict) and set(value) <= FIELDS, "unknown manifest field")
    require(value.get("kind") == "donutgram.plugin" and type(value.get("schemaVersion")) is int and value["schemaVersion"] == 1, "unsupported schema")
    require(isinstance(value.get("id"), str) and len(value["id"]) <= 128 and re.fullmatch(r"[a-z](?:[a-z0-9-]*[a-z0-9])?(\.[a-z](?:[a-z0-9-]*[a-z0-9])?){2,}", value["id"]), "invalid plugin id")
    string(value.get("name"), 80, 1)
    require(value["name"].strip(), "empty name")
    string(value.get("description"), 4096)
    semver(value.get("version"))
    require(value.get("apiVersion") in {"^1.0.0", "1.0.0"}, "unsupported api")
    client = value.get("minClientVersion", "13.2")
    require(isinstance(client, str) and re.fullmatch(r"[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?", client), "invalid minimum client")
    require(tuple((list(map(int, client.split("."))) + [0])[:3]) <= (13, 2, 0), "newer client required")
    entry = safe_path(value.get("entry", "main.js"))
    require(entry.endswith(".js"), "source entry required")
    profile = value.get("profile", "localPrivate")
    require(profile in {"localPrivate", "publicNetwork"}, "invalid profile")
    if "icon" in value:
        require(safe_path(value["icon"]).startswith("assets/"), "icon must be a local asset")
    if "author" in value:
        author = value["author"]
        require(isinstance(author, dict) and set(author) <= {"name", "username"}, "invalid author")
        string(author.get("name"), 128)
        if "username" in author:
            string(author["username"], 64)
    if "changelog" in value:
        string(value["changelog"], 8192)
    seen = set()
    for key in ["permissions", "optionalPermissions"]:
        permissions = value.get(key, [] if key == "optionalPermissions" else None)
        require(isinstance(permissions, list) and len(permissions) <= 32, "invalid permissions")
        for permission in permissions:
            require(isinstance(permission, dict) and set(permission) <= {"capability", "scope", "reason", "origins"}, "invalid permission fields")
            capability, scope = permission.get("capability"), permission.get("scope")
            require(isinstance(capability, str) and capability in SCOPES and scope in SCOPES[capability], "invalid capability scope")
            require((capability, scope) not in seen, "duplicate permission")
            seen.add((capability, scope))
            string(permission.get("reason"), 512, 1)
            origins = permission.get("origins", [])
            require(isinstance(origins, list) and len(origins) <= 16 and all(isinstance(origin, str) for origin in origins) and len(set(origins)) == len(origins), "invalid origins")
            require(profile != "publicNetwork" or capability not in PRIVATE, "network profile cannot read private data")
            require(profile != "localPrivate" or capability not in {"network.public", "notifications.local"}, "private profile cannot export data")
            if capability == "network.public":
                require(origins and profile == "publicNetwork", "network requires origins and publicNetwork")
                for origin in origins:
                    parsed = urlsplit(origin)
                    host = parsed.hostname or ""
                    require(origin == "https://" + host and re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}", host) and not host.endswith((".local", ".internal", ".localhost")), "invalid public https origin")
            else:
                require(not origins, "unexpected origins")
    if "settingsSchema" in value:
        settings = value["settingsSchema"]
        require(isinstance(settings, dict) and set(settings) == {"type", "properties"} and settings["type"] == "object" and isinstance(settings["properties"], dict) and len(settings["properties"]) <= 32, "invalid settings schema")
        for key, field in settings["properties"].items():
            require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", key) and isinstance(field, dict) and set(field) <= {"type", "title", "description", "default", "minimum", "maximum", "maxLength", "enum"}, "invalid settings field")
            require(field.get("type") in {"boolean", "string", "number", "integer"}, "unsupported setting type")
            string(field.get("title"), 128, 1)
            if "default" in field:
                default, kind = field["default"], field["type"]
                require((kind == "boolean" and type(default) is bool) or (kind == "string" and isinstance(default, str) and len(default) <= 4096) or (kind in {"number", "integer"} and type(default) in {int, float} and math.isfinite(default) and (kind != "integer" or int(default) == default)), "invalid setting default")
    return value

def validate_files(files, metadata):
    require(0 < len(files) <= 128 and sum(map(len, files.values())) <= 4 * 1024 * 1024, "runtime package limits")
    names = set()
    for name, data in files.items():
        safe_path(name)
        require(name.lower() not in names, "case-colliding package paths")
        names.add(name.lower())
        require(len(data) <= 1024 * 1024 and Path(name).suffix.lower() in {".js", ".json", ".png", ".jpg", ".jpeg", ".webp"}, "unsupported or oversized resource")
        if name.endswith(".js"):
            try:
                text = data.decode("utf-8")
            except UnicodeError as error:
                raise ValidationError("invalid utf8 source") from error
            require("\0" not in text, "source contains nul")
    entry = metadata.get("entry", "main.js")
    require(entry in files, "entry missing")
    marker(files[entry].decode("utf-8"))
    for name in names:
        parent = name.rpartition("/")[0]
        while parent:
            require(parent not in names, "file directory collision")
            parent = parent.rpartition("/")[0]
    return metadata, files

def read_package(path):
    path = Path(path)
    if path.is_dir():
        files = {}
        total = 0
        for item in sorted(path.rglob("*")):
            require(not item.is_symlink(), "symlinks are forbidden")
            if item.is_file():
                require(item.stat().st_size <= 1024 * 1024, "file limit")
                require(len(files) < 128, "file count limit")
                total += item.stat().st_size
                require(total <= 4 * 1024 * 1024, "runtime package limit")
                files[item.relative_to(path).as_posix()] = item.read_bytes()
        require("manifest.json" in files, "manifest missing")
        metadata = manifest(decode_json(files["manifest.json"].decode("utf-8"))[0])
        return validate_files(files, metadata)
    require(path.stat().st_size <= 8 * 1024 * 1024, "package limit")
    data = path.read_bytes()
    if path.name.lower().endswith(".donut.js"):
        metadata = manifest(single_manifest(data.decode("utf-8")))
        require(metadata.get("entry", "main.js") == "main.js", "single-file entry must be main.js")
        return validate_files({"main.js": data}, metadata)
    require(path.suffix.lower() == ".dgplugin", "unsupported plugin format")
    files, names, total = {}, set(), 0
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        require(0 < len(archive.infolist()) <= 128, "archive count limit")
        for info in archive.infolist():
            name = safe_path(info.filename[:-1] if info.is_dir() else info.filename)
            require(name.lower() not in names, "duplicate zip entry")
            names.add(name.lower())
            mode = (info.external_attr >> 16) & 0xf000
            require(mode in {0, stat.S_IFDIR if info.is_dir() else stat.S_IFREG}, "zip links or special files forbidden")
            require(info.flag_bits & ~0x800 == 0 and info.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}, "unsupported zip flags or method")
            total += info.file_size
            require(info.file_size <= 1024 * 1024 and total <= 4 * 1024 * 1024 and info.file_size <= max(1024 * 1024, info.compress_size * 200), "zip size limit")
            offset = info.header_offset
            require(data[offset:offset+4] == b"PK\x03\x04", "bad zip local header")
            fields = struct.unpack_from("<HHHHHIIIHH", data, offset+4)
            require(fields[1] == info.flag_bits and fields[2] == info.compress_type and fields[5] == info.CRC and fields[6] == info.compress_size and fields[7] == info.file_size, "zip header mismatch")
            raw_name = data[offset+30:offset+30+fields[8]]
            require(raw_name.decode("utf-8") == info.filename, "zip name mismatch")
            if not info.is_dir():
                with archive.open(info) as source:
                    contents = source.read(info.file_size + 1)
                require(len(contents) == info.file_size, "zip actual size mismatch")
                files[name] = contents
            else:
                require(info.file_size == 0, "invalid directory")
    require("manifest.json" in files, "manifest missing")
    metadata = manifest(decode_json(files["manifest.json"].decode("utf-8"))[0])
    return validate_files(files, metadata)

def pack(source, destination):
    metadata, files = read_package(source)
    output = Path(destination)
    require(output.suffix == ".dgplugin", "output must end in .dgplugin")
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o600) << 16
            archive.writestr(info, data)
    require(len(buffer.getvalue()) <= 8 * 1024 * 1024, "output limit")
    output.write_bytes(buffer.getvalue())
    return metadata

def create(destination, identity):
    target = Path(destination)
    require(not target.exists(), "destination already exists")
    value = {"kind": "donutgram.plugin", "schemaVersion": 1, "id": identity, "name": "my plugin", "version": "1.0.0", "description": "local composer command", "apiVersion": "^1.0.0", "permissions": [{"capability": "ui.contribute", "scope": "composer", "reason": "show my command"}], "entry": "main.js", "profile": "localPrivate"}
    manifest(value)
    target.mkdir(parents=True)
    (target / "manifest.json").write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (target / "main.js").write_text('const _plugin = "donutgram";\nexport default definePlugin({async activate(api) {await api.commands.register({id:"hello",title:"hello",placement:"composer",async run(){await api.ui.toast("hello");}});}});\n', encoding="utf-8")

def mock_test(source, fixture):
    metadata, files = read_package(source)
    with tempfile.TemporaryDirectory(prefix="dgplugin-mock-") as directory:
        snapshot = Path(directory) / "package.json"
        snapshot.write_text(json.dumps({"manifest": metadata, "files": {key: value.decode("utf-8") for key, value in files.items() if key.endswith(".js")}}), encoding="utf-8")
        process = subprocess.run(["node", "--experimental-vm-modules", str(ROOT / "tools/mock-host.mjs"), str(snapshot), str(Path(fixture).resolve())], timeout=5, capture_output=True, text=True)
        require(process.returncode == 0, process.stderr.strip() or "mock host failed")
        return json.loads(process.stdout)

def main():
    parser = argparse.ArgumentParser(prog="dgplugin")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["validate", "compatibility"]:
        child = commands.add_parser(name)
        child.add_argument("source")
    child = commands.add_parser("pack")
    child.add_argument("source")
    child.add_argument("destination")
    child = commands.add_parser("create")
    child.add_argument("destination")
    child.add_argument("--id", required=True)
    child = commands.add_parser("test")
    child.add_argument("source")
    child.add_argument("fixture")
    args = parser.parse_args()
    try:
        if args.command == "create":
            create(args.destination, args.id)
            result = {"created": args.destination}
        elif args.command == "pack":
            metadata = pack(args.source, args.destination)
            result = {"id": metadata["id"], "package": args.destination, "sha256": hashlib.sha256(Path(args.destination).read_bytes()).hexdigest()}
        elif args.command == "test":
            result = mock_test(args.source, args.fixture)
        else:
            metadata, files = read_package(args.source)
            result = {"id": metadata["id"], "version": metadata["version"], "files": len(files), "apiVersion": "1.0.0"}
            if args.command == "compatibility":
                result.update({"minimumClient": metadata.get("minClientVersion", "13.2"), "profile": metadata.get("profile", "localPrivate"), "sdkFamilies": AVAILABLE, "requiresRuntimeAvailabilityCheck": True, "iosVisualVerification": False})
            result["signatureVerification"] = "native_installer_required"
        print(json.dumps(result, ensure_ascii=False))
    except (ValidationError, OSError, UnicodeError, zipfile.BadZipFile, subprocess.SubprocessError, KeyError, TypeError, OverflowError, RuntimeError, struct.error) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
