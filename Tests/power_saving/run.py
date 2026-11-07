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
    fixture = Path(__file__).with_name("fixtures.swift.in").read_text(encoding="utf-8")
    fixture = fixture.replace("SETTINGS_IMPLEMENTATION", (settings + "\n" + threshold).replace("public ", ""))
    fixture = fixture.replace("PANEL_IMPLEMENTATION", metrics)
    animation_node = read("submodules/AnimationUI/Sources/AnimationNode.swift")
    sticker_node = read("submodules/AnimatedStickerNode/Sources/AnimatedStickerNode.swift")
    playback = Path(__file__).with_name("playback.swift.in").read_text(encoding="utf-8")
    replacements = {
        "ANIMATION_PLAY_IMPLEMENTATION": block(animation_node, "public func play()"),
        "STICKER_UPDATE_IMPLEMENTATION": block(sticker_node, "private func updateIsPlaying()"),
        "STICKER_PLAY_IMPLEMENTATION": block(sticker_node, "public func play(firstFrame: Bool = false,").split("        if self.isSetUpForPlayback {")[0],
        "STICKER_PAUSE_IMPLEMENTATION": block(sticker_node, "public func pause()"),
        "STICKER_STOP_IMPLEMENTATION": block(sticker_node, "public func stop()"),
        "STICKER_SEEK_IMPLEMENTATION": block(sticker_node, "public func seekTo(_ position:").split("        let directData = self.directData")[0],
    }
    for marker, implementation in replacements.items():
        assert marker in playback
        playback = playback.replace(marker, implementation.replace("public ", "").replace("private ", ""))
        assert marker not in playback
    fixture += "\n" + playback
    native = read("submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIViewController+Navigation.m")
    animation = block(native, "CAAnimation *animationForEnhancedPowerSaving(")
    native_fixture = Path(__file__).with_name("animations.m.in").read_text(encoding="utf-8").replace("ANIMATION_IMPLEMENTATION", animation)
    native_replacements = {
        "POWER_SAVING_STATE_IMPLEMENTATION": "static atomic_bool enhancedPowerSavingEnabled = false;\n" + block(native, "bool getEnhancedPowerSavingEnabled(") + "\n" + block(native, "void setEnhancedPowerSavingEnabled("),
        "ANIMATION_RESTORATION_IMPLEMENTATION": native[native.index("static NSMapTable<CALayer *, NSMutableDictionary<NSString *, CAAnimation *> *> *enhancedPowerSavingAnimations("):native.index("@interface UIViewControllerPresentingProxy")],
        "ANIMATION_REMOVE_IMPLEMENTATION": block(native, "- (void)_65087dc8_removeAnimationForKey:"),
        "ANIMATION_REMOVE_ALL_IMPLEMENTATION": block(native, "- (void)_65087dc8_removeAllAnimations"),
    }
    for marker, implementation in native_replacements.items():
        assert marker in native_fixture
        native_fixture = native_fixture.replace(marker, implementation)
        assert marker not in native_fixture
    assert "animationForEnhancedPowerSavingOnLayer(self, updatedAnimation, key)" in block(native, "- (void)_65087dc8_addAnimation:")
    policy = read("submodules/Display/Source/EnhancedPowerSaving.swift")
    assert "layer.add(animation, forKey: key)" in policy
    assert "restoreAnimationsAfterEnhancedPowerSaving()" in policy
    assert "SETTINGS_IMPLEMENTATION" not in fixture
    assert "PANEL_IMPLEMENTATION" not in fixture
    assert "ANIMATION_IMPLEMENTATION" not in native_fixture
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
