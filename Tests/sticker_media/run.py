import pathlib
import argparse
import shutil
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


root = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--source-only", action="store_true")
args = parser.parse_args()
policy = (root / "submodules/TelegramCore/Sources/Donutgram/DonutgramStickerMedia.swift").read_text(encoding="utf-8")
policy = policy.replace("import Postbox\n", "").replace("import DGSimpleSettings\n", "")
policy = policy.replace("public func ", "func ").replace("DGSimpleSettings.shared", "testSettings")
fixture = pathlib.Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
conversion = (root / "submodules/TelegramUI/Sources/ChatController+DonutgramStickerMedia.swift").read_text(encoding="utf-8")
progress = block(conversion, "private final class DonutgramStickerMediaProgress")
assert "donutgramStickerSignalQueue = Queue(queue: donutgramStickerExportQueue)" in conversion
for converter in ("donutgramStaticStickerMedia", "donutgramStickerMedia"):
    assert "|> deliverOn(donutgramStickerSignalQueue)" in block(conversion, f"private func {converter}(")
assert "present(controller, in: .current, completion: completion)" in block(conversion, "func donutgramMessagesWithStickerMedia(")
sync = (root / "submodules/TelegramCore/Sources/SyncCore/SyncCore_SynchronizeableChatInputState.swift").read_text(encoding="utf-8")
chat_list = (root / "submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift").read_text(encoding="utf-8")
entries = (root / "submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift").read_text(encoding="utf-8")
draft_checks = "\nextension DraftInputState {\n" + block(sync, "public var isEmptyReply:").replace("public ", "") + "\n" + block(sync, "func chatListTimestamp(") + "\n}\n"
draft_checks += "enum EngineChatList {\n" + block(chat_list, "public struct Draft:").replace("public ", "") + "\n}\n"
draft_checks += block(entries, "private func chatListDraftState(") + "\n"
draft_checks += pathlib.Path(__file__).with_name("draft_fixtures.swift").read_text(encoding="utf-8")
draft_refresh = (root / "submodules/TelegramCore/Sources/Donutgram/DonutgramEmptyReplyDrafts.swift").read_text(encoding="utf-8")
draft_checks += "\n" + block(draft_refresh, "func donutgramRefreshEmptyReplyDraftTimestamps(")
draft_checks += "\n" + pathlib.Path(__file__).with_name("stored_draft_fixtures.swift").read_text(encoding="utf-8")
account = (root / "submodules/TelegramCore/Sources/Account/Account.swift").read_text(encoding="utf-8")
assert "managedDonutgramEmptyReplyDrafts(postbox: self.postbox).start()" in account
# The chat states table has integer keys: a blob scan hands back their decimal text, not peer ids.
state_table = (root / "submodules/Postbox/Sources/PeerChatInterfaceStateTable.swift").read_text(encoding="utf-8")
assert "self.valueBox.scanInt64(self.table, keys:" in block(state_table, "func getAllPeerIds()")
# A launch with the switch unchanged skips the scan; a flip re-sorts the drafts, then records the value.
managed = block(draft_refresh, "func managedDonutgramEmptyReplyDrafts(")
assert managed.index("getPreferencesEntry(key: donutgramEmptyReplyDraftsPreferencesKey)") < managed.index("donutgramRefreshEmptyReplyDraftTimestamps(") < managed.index("setPreferencesEntry(key: donutgramEmptyReplyDraftsPreferencesKey")
bot_card = (root / "submodules/TelegramUI/Components/Chat/ChatBotInfoItem/Sources/ChatBotInfoItem.swift").read_text(encoding="utf-8")
assert "flags: [.Incoming]" in block(bot_card, "private func openMedia()")
location = (root / "submodules/ChatListUI/Sources/Node/ChatListNodeLocation.swift").read_text(encoding="utf-8")
node = (root / "submodules/ChatListUI/Sources/Node/ChatListNode.swift").read_text(encoding="utf-8")
assert location.count("isEmptyReply: opaqueState.synchronizeableInputState?.isEmptyReply ?? false") == 3
assert "isEmptyReply: opaqueState.synchronizeableInputState?.isEmptyReply ?? false" in chat_list
assert entries.count("hideEmptyReplies: hideEmptyReplyDrafts)") == 2
assert "DGSimpleSettings.shared.hideEmptyReplyDrafts" in node and "$0.2 == $1.2" in node
# A hidden empty reply leaves its chat in place: both ways a draft gets stored skip its time.
peers = (root / "submodules/TelegramCore/Sources/TelegramEngine/Peers/TelegramEnginePeers.swift").read_text(encoding="utf-8")
hidden_reply_time = "overrideChatTimestamp = inputState.chatListTimestamp(hidingEmptyReplies: DGSimpleSettings.shared.hideEmptyReplyDrafts)"
assert hidden_reply_time in block(sync, "func _internal_updateChatInputState(")
assert hidden_reply_time in block(peers, "public func setOpaqueChatInterfaceState(")
if args.source_only:
    print("sticker media and empty reply integration checks passed; Swift behavior was not executed")
    raise SystemExit(0)
swift = shutil.which("swiftc")
if not swift:
    raise SystemExit("swiftc is required")
with tempfile.TemporaryDirectory(prefix="donutgram-sticker-media-") as temporary:
    temporary = pathlib.Path(temporary)
    main = temporary / "main.swift"
    main.write_text(policy + "\n" + progress + "\n" + fixture + draft_checks, encoding="utf-8")
    executable = temporary / "checks"
    settings = sorted((root / "Donutgram/DGSimpleSettings/Sources").glob("*.swift"))
    subprocess.run([swift, "-warnings-as-errors", *map(str, settings), str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    video_main = temporary / "video" / "main.swift"
    video_main.parent.mkdir()
    video_fixture = pathlib.Path(__file__).with_name("video_fixture.swift").read_text(encoding="utf-8")
    writer = block(conversion, "private func donutgramStickerVideo(")
    video_main.write_text(video_fixture.replace("// PRODUCTION WRITER", writer), encoding="utf-8")
    video_executable = temporary / "video" / "checks"
    subprocess.run([swift, "-warnings-as-errors", str(video_main), "-o", str(video_executable)], check=True)
    subprocess.run([str(video_executable)], check=True)
    # A Swift file the change deletes has nothing to parse.
    changed = subprocess.check_output(["git", "diff", "--name-only", "--diff-filter=d", "origin/master...HEAD", "--", "*.swift"], cwd=root, text=True)
    for path in changed.splitlines():
        subprocess.run([swift, "-frontend", "-parse", str(root / path)], check=True)
