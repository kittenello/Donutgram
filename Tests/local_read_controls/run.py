"""Compile production local-read code against fixtures; verify real settings across processes."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

def prepare():
    ghost = source("submodules/TelegramCore/Sources/Donutgram/DonutgramGhostLocalRead.swift")
    ghost = "\n".join(line for line in ghost.splitlines() if not line.startswith("import "))
    bulk = source("submodules/TelegramCore/Sources/TelegramEngine/Messages/DonutgramReadAllMessages.swift")
    bulk = bulk[bulk.index("func _internal_donutgramReadAllMessagesLocally"):]
    assert "network" not in bulk and "applyInteractiveRead" not in bulk
    push = source("submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift")
    assert "if donutgramGhostLocalReadState(accountPeerId:" in push
    entries = source("submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift")
    assert "groupItems.removeAll { $0.id == .archive }" in entries
    node = source("submodules/ChatListUI/Sources/Node/ChatListNode.swift")
    assert "combineLatest(hideArchivedFolderByDefault, fullyHideArchive)" in node
    input_context = source("submodules/TelegramUI/Sources/ChatInterfaceInputContexts.swift")
    assert "if !DGSimpleSettings.shared.hideGiftButton, isTextEmpty, showPremiumGift" in input_context
    settings_items = source("submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift")
    assert "allowsClearing: true" in settings_items
    for path in ["Donutgram/DGSimpleSettings/Sources/DGSimpleSettings.swift", "submodules/ChatListUI/Sources/ChatListControllerNode.swift"]:
        assert "openArchiveOnPull" not in source(path)
    # The switch is gone; its old links lead to the archive switch.
    features = source("Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift")
    assert [line.strip() for line in features.splitlines() if "openArchiveOnPull" in line] == ['if page == .chats && key == "openArchiveOnPull" {']
    assert 'focusKey = "hideArchive"' in features and "updateChatArchiveSettings" not in features
    controller_node = source("submodules/ChatListUI/Sources/ChatListControllerNode.swift")
    assert "if isPrimary {\n                                    self.mainContainerNode.currentItemNode.revealScrollHiddenItem()" in controller_node
    return Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8").replace("// PRODUCTION", ghost + "\n" + bulk)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    harness = prepare()
    if args.source_only:
        print("source integration checks passed")
    else:
        compiler = shutil.which("swiftc")
        if not compiler:
            raise SystemExit("swiftc is required for behavior and persistence checks")
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            main = directory / "main.swift"
            main.write_text(harness, encoding="utf-8")
            executable = directory / "checks"
            subprocess.run([compiler, *map(str, (ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift")), str(main), "-o", str(executable)], check=True)
            suite = "donutgram-local-read-" + uuid.uuid4().hex
            for mode in ["write", "read"]:
                subprocess.run([str(executable), mode, suite], check=True)
