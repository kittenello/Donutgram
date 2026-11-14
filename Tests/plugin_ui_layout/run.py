from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swiftc")
    parser.add_argument("--sdk")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    swift = args.swiftc or shutil.which("swiftc")
    if not swift:
        raise SystemExit("swiftc is required for plugin geometry checks")
    with tempfile.TemporaryDirectory(prefix="donutgram-plugin-layout-") as temporary:
        directory = Path(temporary)
        source = directory / "main.swift"
        source.write_text(Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8"), encoding="utf-8")
        executable = directory / "checks.exe"
        options = ["-sdk", args.sdk] if args.sdk else []
        subprocess.run([swift, *options, "-swift-version", "5", str(root / "Donutgram/DGPluginsUI/Sources/DGPluginLayout.swift"), str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=15)


if __name__ == "__main__":
    main()
