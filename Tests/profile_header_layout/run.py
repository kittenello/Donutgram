from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift"


def main():
    source = SOURCE.read_text(encoding="utf-8")
    start = source.index("\n", source.index("let apparentBackgroundHeight =")) + 1
    end = source.index("\n        if displayStandardTitle {", start)
    layout = source[start:end]
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    fixture = fixture.replace("        fatalError(\"production layout\")", layout)
    compiler = shutil.which("swiftc")
    if compiler is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="profile-header-layout-") as directory:
        directory = Path(directory)
        main_file = directory / "main.swift"
        executable = directory / "layout-tests"
        main_file.write_text(fixture, encoding="utf-8")
        subprocess.run([compiler, str(main_file), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        subprocess.run([compiler, "-frontend", "-parse", str(SOURCE)], check=True)


if __name__ == "__main__":
    main()
