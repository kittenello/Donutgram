from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[2]
CAMERA = "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift"
ENTRIES = "submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift"
HEADER = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def prepare():
    camera = read(CAMERA)
    model = block(camera, "private struct RoundVideoRecordingCountdown")
    assert "self.node.withReadyCamera" in block(camera, "fileprivate func beginRecordingCountdown")
    assert "RunLoop.main.add(timer, forMode: .common)" in camera
    for marker in ["public func stopVideoRecording() -> Bool", "public func sendVideoRecording(", "fileprivate func requestDismiss(animated:"]:
        assert "self.cancelRecordingCountdown()" in block(camera, marker)
    assert "self.recordingStartGeneration == generation" in camera
    assert "controller.recordingStartGeneration == generation" in camera
    assert "UIApplication.willResignActiveNotification" in camera
    start = camera.index("self.resultDisposable.set((camera.startRecording()")
    assert "controller.recordingStartTime = CACurrentMediaTime()" in camera[start - 250:start]
    ui = read("Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift")
    for key in ["localVerification", "roundVideoCountdown", "hideProxySponsor"]:
        assert f'"{key}"' in ui
    header = read(HEADER)
    loader = block(header, "private func localVerificationIcon(peer:")
    assert "peer.id == self.context.account.peerId" in loader
    assert "self.isSettings || self.isMyProfile" in loader
    assert "verifierSettings?.iconFileId" in loader
    assert "hideProxySponsor" in read("submodules/ChatListUI/Sources/Node/ChatListNode.swift")
    entries = read(ENTRIES)
    filtering = block(entries, "let filteredAdditionalItemEntries = view.additionalItems.filter")
    assert entries.index(filtering) < entries.index("pinnedIndexOffset += UInt16(filteredAdditionalItemEntries.count)")
    filtering = filtering.replace("view.additionalItems", "items").replace("DGSimpleSettings.shared", "settings")
    filtering = "func filterItems(_ items: [Item], settings: DGSimpleSettings, state: ListState) -> [Item] {\n" + filtering + "\nreturn filteredAdditionalItemEntries\n}\n"
    return model + "\n" + filtering + Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    harness = prepare()
    if args.source_only:
        print("local profile, proxy sponsor and countdown integration checks passed")
    else:
        swift = shutil.which("swiftc")
        if not swift:
            raise SystemExit("swiftc is required for behavior checks")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            main = directory / "main.swift"
            main.write_text("import Foundation\n" + harness, encoding="utf-8")
            executable = directory / "checks"
            settings = (ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift")
            subprocess.run([swift, "-warnings-as-errors", *map(str, settings), str(main), "-o", str(executable)], check=True)
            suite = "donutgram-local-profile-" + uuid.uuid4().hex
            for mode in ["write", "read"]:
                subprocess.run([str(executable), mode, suite], check=True)
            for path in [CAMERA, ENTRIES, HEADER, "Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift", "Donutgram/DGSettingsUI/Sources/DGSettingsController.swift", "submodules/ChatListUI/Sources/Node/ChatListNode.swift"]:
                subprocess.run([swift, "-frontend", "-parse", str(ROOT / path)], check=True)
