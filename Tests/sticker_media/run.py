import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
swift = shutil.which("swiftc")
if not swift:
    raise SystemExit("swiftc is required")
policy = (root / "submodules/TelegramCore/Sources/Donutgram/DonutgramStickerMedia.swift").read_text(encoding="utf-8")
policy = policy.replace("import Postbox\n", "").replace("import DGSimpleSettings\n", "")
policy = policy.replace("public func ", "func ").replace("DGSimpleSettings.shared", "testSettings")
fixture = pathlib.Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
with tempfile.TemporaryDirectory(prefix="donutgram-sticker-media-") as temporary:
    temporary = pathlib.Path(temporary)
    main = temporary / "main.swift"
    main.write_text(policy + "\n" + fixture, encoding="utf-8")
    executable = temporary / "checks"
    settings = sorted((root / "Donutgram/DGSimpleSettings/Sources").glob("*.swift"))
    subprocess.run([swift, "-warnings-as-errors", *map(str, settings), str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    changed = subprocess.check_output(["git", "diff", "--name-only", "origin/master...HEAD", "--", "*.swift"], cwd=root, text=True)
    for path in changed.splitlines():
        subprocess.run([swift, "-frontend", "-parse", str(root / path)], check=True)
