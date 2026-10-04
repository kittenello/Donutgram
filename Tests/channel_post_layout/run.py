"""Compile production photo sizing and mosaic layout with geometry regression cases."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CHAT = ROOT / "submodules/TelegramUI/Components/Chat"
COMMON = CHAT / "ChatMessageItemCommon/Sources"
HELPERS = COMMON / "DonutgramChannelPostLayout.swift"
MOSAIC = ROOT / "submodules/MosaicLayout/Sources/ChatMessageBubbleMosaicLayout.swift"


def check_integration():
    bubble = (CHAT / "ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift").read_text(encoding="utf-8")
    media = (CHAT / "ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift").read_text(encoding="utf-8")
    common = (COMMON / "ChatMessageItemCommon.swift").read_text(encoding="utf-8")
    assert "public var wideChannelPost: Bool = false" in common
    assert "layoutConstants.wideChannelPost = wideChannelPost" in bubble
    start = bubble.index("if wideChannelPost {\n            // A channel post uses")
    end = bubble.index("var maximumContentWidth", start)
    assert "needsShareButton = false" in bubble[start:end]
    assert "baseWidth - deliveryFailedInset" in bubble[start:end]
    assert "firstMessage.id.peerId == chatLocationPeerId" in bubble
    assert "!firstMessage.media.contains(where: { ($0 as? TelegramMediaFile)?.isInstantVideo == true })" in bubble
    assert "case .broadcast = channel.info, firstMessage.adAttribute == nil" in bubble
    assert "if wideChannelPost && !hideBackground" not in bubble
    assert "mosaicLimit.width = availableMediaWidth" in bubble
    assert "donutgramChannelMosaicWidth(" in bubble
    assert "if layoutConstants.wideChannelPost" in media
    assert "donutgramChannelPhotoSizeLimit(" in media
    assert "donutgramChannelPhotoHeight(" in media
    assert "hasCaption: !message.text.isEmpty" in media
    return [
        COMMON / "ChatMessageItemCommon.swift", HELPERS,
        CHAT / "ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift",
        CHAT / "ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift",
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    sources = check_integration()
    if args.source_only:
        print("Channel width, side-button and media-layout source checks passed; Swift execution was not run.")
        return
    swift = shutil.which("swiftc")
    if swift is None:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-channel-layout-") as directory:
        directory = Path(directory)
        fixture = directory / "main.swift"
        fixture.write_text(Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8"), encoding="utf-8")
        executable = directory / "layout-tests"
        subprocess.run([swift, "-warnings-as-errors", str(HELPERS), str(MOSAIC), str(fixture), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        for source in sources:
            subprocess.run([swift, "-frontend", "-parse", str(source)], check=True)


if __name__ == "__main__":
    main()
