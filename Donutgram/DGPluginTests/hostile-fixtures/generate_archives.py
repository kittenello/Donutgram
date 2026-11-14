import argparse
import io
import json
import struct
import zipfile
from pathlib import Path


def archive(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as result:
        for name, data in entries:
            result.writestr(name, data)
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    metadata = {"kind": "donutgram.plugin", "schemaVersion": 1, "id": "dev.donutgram.fixture-archive", "name": "archive fixture", "version": "1.0.0", "description": "hostile archive", "apiVersion": "^1.0.0", "permissions": []}
    source = b'const _plugin = "donutgram"; export default definePlugin({activate(){}});'
    base = [("manifest.json", json.dumps(metadata).encode()), ("main.js", source)]
    cases = {
        "valid.deflate.dgplugin": archive(base),
        "traversal.dgplugin": archive(base + [("../escape.js", b"escape")]),
        "case-collision.dgplugin": archive(base + [("MAIN.js", source)]),
        "expanded-limit.dgplugin": archive(base + [("assets/large.json", b"0" * (1024 * 1024 + 1))]),
        "file-count.dgplugin": archive(base + [(f"modules/{index}.js", b"export const x=1;") for index in range(128)]),
        "nested.dgplugin": archive(base + [("assets/hidden.json", archive(base))]),
    }
    symlink = io.BytesIO()
    with zipfile.ZipFile(symlink, "w") as result:
        for name, data in base:
            result.writestr(name, data)
        info = zipfile.ZipInfo("modules/link.js")
        info.create_system = 3
        info.external_attr = 0o120777 << 16
        result.writestr(info, b"../../outside")
    cases["symlink.dgplugin"] = symlink.getvalue()
    corrupt = bytearray(cases["valid.deflate.dgplugin"])
    local_crc_offset = 14
    struct.pack_into("<I", corrupt, local_crc_offset, 0)
    cases["mismatched-local-crc.dgplugin"] = corrupt
    for name, data in cases.items():
        (args.output / name).write_bytes(data)
    print(f"generated {len(cases)} archives in {args.output}")


if __name__ == "__main__":
    main()
