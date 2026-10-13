"""Exercise actual settings and sticker-description rendering on macOS."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
REPLY = "submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift"
PREVIEW = "submodules/SettingsUI/Sources/Themes/ThemeSettingsChatPreviewItem.swift"

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
    reply = read(REPLY)
    start = reply.index("                if isMediaValue && DGSimpleSettings.shared.hideStickerReplyEmoji")
    end = reply.index("                isMedia = isMediaValue", start)
    description = reply[start:end]
    assert "arguments.strings.Message_Sticker" in description and ".isSticker == true" in description
    assert "replyDecorationOptions(isSticker: isStickerReply)" in reply
    assert "replyForward?.quote?.media as? TelegramMediaFile" in reply
    assert "replyOptions & 2 != 0, let backgroundEmojiId" in reply
    assert "if replyOptions & 2 == 0" in reply  # collectible decoration is hidden as well
    ui = read("Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift")
    for key in ["hideStickerReplyColors", "hideStickerReplyEmoji", "hideStickerReplyBackground", "hidePremiumReplyEmoji"]:
        assert f'"{key}"' in ui
    assert ".stickerReplies(" not in ui and "dgStickerRepliesController" not in ui
    entries = read("Donutgram/DGSettingsUI/Sources/DGSettingsController.swift")
    assert "ItemListExpandableSwitchItem" not in entries
    assert "DGMessagePreviewConfiguration, TelegramMediaFile?" in entries
    preview = read(PREVIEW)
    start = preview.index("public func donutgramMessagePreviewItem")
    end = preview.index("public func donutgramStickerPreviewItem", start)
    assert preview[start:end].count("ChatPreviewMessageItem(") == 4
    assert "TextEntitiesMessageAttribute(entities: messageItem.entities)" in preview
    assert 'username: "donutgram"' in preview
    assert "MessageForwardInfo(author: forwardPeer" in preview
    assert "associatedMedia[emoji.fileId] = emoji" in preview
    assert 'text: messageItem.replySticker == nil ? text : ""' in preview
    assert "currentMessages == item.messageItems" not in preview
    assert "zip(previous, item.messageItems).allSatisfy" in preview
    history = read("submodules/TelegramUI/Sources/ChatHistoryListNode.swift")
    assert "includeAllMessages: stickerRepliesChanged" in history and "|| premiumReplyEmojiChanged)" in history
    contact = read("submodules/TelegramUI/Components/Chat/ChatMessageContactBubbleContentNode/Sources/ChatMessageContactBubbleContentNode.swift")
    assert "if !DGSimpleSettings.shared.hidePremiumReplyEmoji, let contactPeer" in contact
    bg = read("submodules/TelegramUI/Components/Chat/MessageInlineBlockBackgroundView/Sources/MessageInlineBlockBackgroundView.swift")
    predicate = next(line.strip()[3:-2] for line in bg.splitlines() if line.strip().startswith("if previousParams?.primaryColor != params.primaryColor ||"))
    colors = block(reply, "switch arguments.type {\n            case let .bubble(incoming):")
    archive = read("submodules/ChatListUI/Sources/Node/DonutgramArchiveLayout.swift")
    template = Path(__file__).with_name("main.swift").read_text(encoding="utf-8")
    return (template.replace("// PRODUCTION_DESCRIPTION", description)
        .replace("// PRODUCTION_REUSE", block(preview, "func canReuseNode("))
        .replace("// PRODUCTION_BACKGROUND_CONDITION", predicate)
        .replace("// PRODUCTION_REPLY_COLORS", colors)
        .replace("// PRODUCTION_ARCHIVE_LAYOUT", archive))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    harness = prepare()
    if args.source_only:
        print("message control and preview integration checks passed")
    else:
        swift = shutil.which("swiftc")
        if not swift:
            raise SystemExit("swiftc is required for behavior checks")
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            main = temporary / "main.swift"
            main.write_text(harness, encoding="utf-8")
            executable = temporary / "checks"
            settings = (ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift")
            subprocess.run([swift, "-warnings-as-errors", *map(str, settings), str(main), "-o", str(executable)], check=True)
            suite = "donutgram-message-controls-" + uuid.uuid4().hex
            for mode in ["write", "read"]:
                subprocess.run([str(executable), mode, suite], check=True)
            paths = [REPLY, PREVIEW, "Donutgram/DGSettingsUI/Sources/DGSettingsController.swift", "Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift", "submodules/TelegramUI/Sources/ChatHistoryListNode.swift", "submodules/TelegramUI/Components/Chat/ChatMessageContactBubbleContentNode/Sources/ChatMessageContactBubbleContentNode.swift", "submodules/ChatPresentationInterfaceState/Sources/ChatTextFormat.swift", "submodules/ChatListUI/Sources/Node/ChatListNode.swift", "submodules/ChatListUI/Sources/ChatListControllerNode.swift", "submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift", "submodules/TelegramUI/Components/Chat/MessageInlineBlockBackgroundView/Sources/MessageInlineBlockBackgroundView.swift"]
            for path in paths:
                subprocess.run([swift, "-frontend", "-parse", str(ROOT / path)], check=True)
