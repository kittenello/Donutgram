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
sync = (root / "submodules/TelegramCore/Sources/SyncCore/SyncCore_SynchronizeableChatInputState.swift").read_text(encoding="utf-8")
chat_list = (root / "submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift").read_text(encoding="utf-8")
entries = (root / "submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift").read_text(encoding="utf-8")
draft_checks = "\nextension DraftInputState {\n" + block(sync, "public var isEmptyReply:").replace("public ", "") + "\n" + block(sync, "func chatListTimestamp(") + "\n}\n"
draft_checks += "enum EngineChatList {\n" + block(chat_list, "public struct Draft:").replace("public ", "") + "\n}\n"
draft_checks += block(entries, "private func chatListDraftState(") + "\n"
draft_checks += pathlib.Path(__file__).with_name("draft_fixtures.swift").read_text(encoding="utf-8")
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
    print("empty reply integration checks passed; Swift behavior was not executed")
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
    # A Swift file the change deletes has nothing to parse.
    changed = subprocess.check_output(["git", "diff", "--name-only", "--diff-filter=d", "origin/master...HEAD", "--", "*.swift"], cwd=root, text=True)
    for path in changed.splitlines():
        subprocess.run([swift, "-frontend", "-parse", str(root / path)], check=True)

