"""Run real image-cache migration code and ImageIO decoding checks on macOS."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


state = (ROOT / "submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift").read_text()
photos = (ROOT / "submodules/PhotoResources/Sources/PhotoResources.swift").read_text()
helpers = "\n\n".join([
    block(state, "private func copyOrMoveResourceData("),
    block(state, "private func canReusePhotoResourceData("),
    block(state, "func applyMediaResourceChanges(from: Media, to: Media,"),
    block(photos, "private func completePhotoResourceData("),
])
swift = shutil.which("swiftc")
if swift is None:
    raise SystemExit("swiftc is required")
with tempfile.TemporaryDirectory(prefix="avatar-share-") as temporary:
    temporary = Path(temporary)
    main = temporary / "main.swift"
    main.write_text((HERE / "main.swift").read_text().replace("// PRODUCTION_HELPERS", helpers))
    executable = temporary / "checks"
    subprocess.run([swift, "-warnings-as-errors", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    for path in [
        "submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift",
        "submodules/PhotoResources/Sources/PhotoResources.swift",
    ]:
        subprocess.run([swift, "-frontend", "-parse", str(ROOT / path)], check=True)
