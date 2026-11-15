import base64
import hashlib
import json
import math
import re
import struct
from pathlib import Path


def canonical(value):
    if value is None:
        return b"n"
    if type(value) is bool:
        return b"t" if value else b"f"
    if type(value) in {int, float}:
        value = float(value)
        if not math.isfinite(value):
            raise ValueError("nonfinite canonical number")
        return b"d" + struct.pack(">d", 0.0 if value == 0 else value)
    if isinstance(value, str):
        raw = value.encode("utf-8")
        return b"s" + str(len(raw)).encode("ascii") + b":" + raw
    if isinstance(value, list):
        return b"a" + str(len(value)).encode("ascii") + b":" + b"".join(map(canonical, value))
    if isinstance(value, dict):
        keys = sorted(value, key=lambda key: key.encode("utf-8"))
        return b"o" + str(len(keys)).encode("ascii") + b":" + b"".join(canonical(key) + canonical(value[key]) for key in keys)
    raise ValueError("unsupported canonical value")


def generate():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    sdk = Path(__file__).resolve().parents[1]
    values = [None, True, False, -0.0, 0.125, 1e-30, "é/\n雪", {"z": 1, "ä": 2, "a": [None, False, {"nested": -2.75}]}, {"\ue000": 1, "\U00010000": 2}]
    vectors = [{"value": value, "base64": base64.b64encode(canonical(value)).decode(), "sha256": hashlib.sha256(canonical(value)).hexdigest()} for value in values]
    manifest = {"kind": "donutgram.plugin", "schemaVersion": 1, "id": "dev.example.signature-fixture", "name": "signature 雪", "version": "1.0.0", "description": "cross-tool canonical fixture", "apiVersion": "^1.0.0", "permissions": [], "settingsSchema": {"type": "object", "properties": {"fraction": {"type": "number", "title": "fraction", "default": 0.125, "minimum": -2.75, "maximum": 1e30}}}}
    files = {"manifest.json": json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode(), "main.js": b'const _plugin = "donutgram"; definePlugin({activate(){}});'}
    payload = b"donutgram.plugin.signature.v1\n"
    for path in sorted(files):
        content = canonical(manifest) if path == "manifest.json" else files[path]
        payload += str(len(path.encode())).encode() + b":" + path.encode() + b":" + hashlib.sha256(content).hexdigest().encode() + b"\n"
    key = Ed25519PrivateKey.generate()
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    signature = key.sign(payload)
    key.public_key().verify(signature, payload)
    envelope = {"algorithm": "Ed25519", "canonicalization": "dg-canonical-v1", "publicKey": base64.b64encode(public).decode(), "signature": base64.b64encode(signature).decode()}
    files["signature.json"] = json.dumps(envelope, separators=(",", ":")).encode()
    fixture = {"format": "dg-canonical-v1", "vectors": vectors, "files": {path: base64.b64encode(value).decode() for path, value in files.items()}, "payloadBase64": base64.b64encode(payload).decode()}
    raw = (json.dumps(fixture, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    (sdk / "tests/signature-canonical-v1.json").write_bytes(raw)
    test = sdk.parent / "DGPluginInstaller/Tests/DGPluginInstallerTests.swift"
    source = test.read_text(encoding="utf-8")
    source, matches = re.subn(r'(func testCrossToolCanonicalSignatureFixture\(\) throws \{\s+let data = Data\(base64Encoded: ")[A-Za-z0-9+/=]+("\)!)', lambda match: match[1] + base64.b64encode(raw).decode() + match[2], source)
    if matches != 1:
        raise ValueError("cannot synchronize native signature fixture")
    test.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    generate()
