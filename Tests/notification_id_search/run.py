"""Compile production helpers and shared settings against small Postbox fixtures."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/Donutgram"
HELPERS = {
    "DonutgramSpyStorage.swift": [
        "donutgramMessageWithUpdatedLocalTags", "donutgramAllowsSavingInPeer",
        "donutgramPreserveDeletedMessage",
    ],
    "DonutgramNotificationMessages.swift": [
        "donutgramIsNotificationMessage", "donutgramDeleteMessagesFromNotification",
    ],
    "DonutgramUserIdSearch.swift": [
        "donutgramUserIdFromSearchQuery", "donutgramCanOpenIdSearchUser",
        "donutgramAddingUserIdResult",
    ],
}


def extract(source, name):
    start = source.index(f"func {name}(")
    start = source.rfind("\n", 0, start) + 1
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("public func", "func")


def make_harness():
    helpers = "\n".join(
        extract((CORE / file).read_text(encoding="utf-8"), name)
        for file, names in HELPERS.items() for name in names
    )
    fixture = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    assert fixture.count("// PRODUCTION_HELPERS") == 1
    extension = (ROOT / "Telegram/NotificationService/Sources/NotificationService.swift").read_text(encoding="utf-8")
    capture = extension.index("pollSignal = donutgramCaptureNotificationMessage(")
    assert "|> then(pollSignal)" in extension[capture:capture + 650]
    assert "donutgramDeleteMessagesFromNotification(transaction:" in extension
    assert "configureMessagePreservation(appGroupName: appGroupName, isMainApp: false)" in extension
    assert "configureMessagePreservation(appGroupName: appGroupName, isMainApp: true)" in (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
    return fixture.replace("// PRODUCTION_HELPERS", helpers)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    harness = make_harness()
    if args.source_only:
        print("Helper extraction and notification integration source checks passed; Swift execution was not run.")
        return
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-notification-tests-") as directory:
        directory = Path(directory)
        settings_sources = list((ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift"))
        subprocess.run([swift, "-warnings-as-errors", "-emit-library", "-emit-module",
                        "-module-name", "DGSimpleSettings", *map(str, settings_sources),
                        "-o", str(directory / "libDGSimpleSettings.dylib")], cwd=directory, check=True)
        source = directory / "main.swift"
        executable = directory / "notification-tests"
        source.write_text(harness, encoding="utf-8")
        subprocess.run([swift, str(source), "-I", str(directory), "-L", str(directory),
                        "-lDGSimpleSettings", "-Xlinker", "-rpath", "-Xlinker", str(directory),
                        "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        # Use a fresh process to verify that the extension reads persisted settings.
        suite = "donutgram-tests-" + directory.name
        subprocess.run([str(executable), "write-settings", suite], check=True)
        subprocess.run([str(executable), "read-settings", suite], check=True)
        for path in [CORE / file for file in HELPERS] + [
            ROOT / "Telegram/NotificationService/Sources/NotificationService.swift",
            ROOT / "submodules/TelegramCore/Sources/TelegramEngine/Peers/SearchPeers.swift",
            ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift",
        ]:
            subprocess.run([swift, "-frontend", "-parse", str(path)], check=True)


if __name__ == "__main__":
    main()
