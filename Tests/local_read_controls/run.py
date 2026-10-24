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
    # A reply ghost mode posts as scheduled for a few seconds ends a suspicious chat's state, as one sent at once.
    enqueue = source("submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift")
    assert "!$0.1.attributes.contains(where: { ($0 as? OutgoingScheduleInfoMessageAttribute)?.isGhostScheduled == false })" in enqueue
    # The News feed's read mark stays on this device in ghost mode: feed.readFeed reads its channels on the server.
    feed = source("submodules/TelegramCore/Sources/TelegramEngine/Feed/AddedFeedContext.swift")
    commit_read = feed[feed.index("private func commitRead()"):]
    assert commit_read.index("if donutgramGhostModeBlocksContentReads() {") < commit_read.index("#if TELEGRAM_NEWS_FEED_API")
    # A feed page refreshes a stored post the way an edit update does, Donutgram's local state included.
    pages = source("submodules/TelegramCore/Sources/TelegramEngine/Feed/FeedPageStorage.swift")
    assert ".update(donutgramMergedServerMessageUpdate(transaction: transaction, previous: previousMessage, updated: storeMessage))" in pages
    assert "mergedServerMessageUpdate(previous:" not in pages
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
    assert [line.strip() for line in features.splitlines() if "openArchiveOnPull" in line] == ['case "openArchiveOnPull":']
    assert 'case "openArchiveOnPull":\n        // Links to rows that are gone lead to the switches that replaced them.\n        return (.mainScreen, "hideArchive")' in features
    assert "updateChatArchiveSettings" not in features
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
