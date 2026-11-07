from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def prepare():
    settings = block(read("submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift"), "public struct EnergyUsageSettings:")
    threshold = block(read("submodules/TelegramPresentationData/Sources/PresentationData.swift"), "public func automaticEnergyUsageShouldBeOnNow(")
    panel = read("submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift")
    metrics = block(panel, "private func calculateTextFieldMetrics(").replace("private func", "func", 1)
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    fixture = fixture.replace("SETTINGS_IMPLEMENTATION", settings + "\n" + threshold)
    fixture = fixture.replace("PANEL_IMPLEMENTATION", metrics)
    native = read("submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIViewController+Navigation.m")
    animation = block(native, "CAAnimation *animationForEnhancedPowerSaving(")
    native_fixture = Path(__file__).with_name("animations.m").read_text(encoding="utf-8").replace("ANIMATION_IMPLEMENTATION", animation)
    return fixture, native_fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    fixture, native_fixture = prepare()
    if args.source_only:
        print("Production energy policy, composer measurement and animation code extracted; behavior was not executed.")
        return
    compiler = shutil.which("swiftc")
    if compiler is None:
        raise SystemExit("swiftc and the macOS SDK are required")
    with tempfile.TemporaryDirectory(prefix="donutgram-power-saving-") as directory:
        directory = Path(directory)
        source = directory / "main.swift"
        source.write_text(fixture, encoding="utf-8")
        executable = directory / "policy-checks"
        subprocess.run([compiler, "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        source = directory / "animations.m"
        source.write_text(native_fixture, encoding="utf-8")
        executable = directory / "animation-checks"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Werror", "-framework", "Foundation", "-framework", "QuartzCore", str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
