from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "submodules/TelegramCore/Sources/ApiUtils/ReactionsMessageAttribute.swift"
HELPERS = ("donutgramRemovedReactions", "donutgramMergeRemovedReactions", "donutgramVisibleMessageReactions")


def extract(source, name):
    start = source.index(f"func {name}(")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    source = SOURCE.read_text(encoding="utf-8")
    helpers = "\n".join(extract(source, name) for name in HELPERS)
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run this check on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-removed-reactions-") as directory:
        directory = Path(directory)
        harness = directory / "main.swift"
        executable = directory / "reaction-tests"
        harness.write_text(fixture.replace("PRODUCTION_HELPERS", helpers), encoding="utf-8")
        subprocess.run([swift, str(harness), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
