"""Check the AAC settings a round video's sound is written with, for every microphone sample rate."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "submodules/Camera/CameraNeo/Sources/RoundVideoAudioSettings.swift"
RECORDER = ROOT / "submodules/Camera/CameraNeo/Sources/VideoRecorder.swift"


def make_harness():
    helper = HELPER.read_text(encoding="utf-8")
    body = helper[helper.index("// Donutgram:"):]
    recorder = RECORDER.read_text(encoding="utf-8")
    # The recorder takes its sound settings from the helper and no longer pins a bit rate of its own.
    assert "roundVideoAudioSettings(formatDescription: formatDescription, canApply:" in recorder
    assert "AVEncoderBitRateKey" not in recorder
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    assert fixture.count("// PRODUCTION_HELPERS") == 1
    return fixture.replace("// PRODUCTION_HELPERS", body)


def main():
    harness = make_harness()
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-round-video-audio-") as directory:
        directory = Path(directory)
        source = directory / "main.swift"
        executable = directory / "round-video-audio-tests"
        source.write_text(harness, encoding="utf-8")
        subprocess.run([swift, str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
