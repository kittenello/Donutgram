"""Compile actual display getters, settings and badge lookup against small peer fixtures."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources"


def block(source, marker):
    start = source.index(marker)
    start = source.rfind("\n", 0, start) + 1
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def harness():
    utils = (CORE / "Utils/PeerUtils.swift").read_text(encoding="utf-8")
    engine = (CORE / "TelegramEngine/Peers/Peer.swift").read_text(encoding="utf-8")
    properties = ["isVerified", "verificationIconFileId", "donutgramDisplayIsVerified", "donutgramDisplayVerificationIconFileId"]
    peer_getters = "\n".join(block(utils, f"var {name}:") for name in properties)
    engine_getters = "\n".join(block(engine, f"var {name}:") for name in properties)
    verification = block((CORE / "SyncCore/SyncCore_TelegramUser.swift").read_text(encoding="utf-8"), "public struct PeerVerification:")
    policy = (CORE / "Donutgram/DonutgramVerificationDisplay.swift").read_text(encoding="utf-8")
    badge = (ROOT / "submodules/TelegramUI/Components/ChatTitleView/Sources/DonutgramTeamBadge.swift").read_text(encoding="utf-8")
    badge_start = badge.index("public enum DonutgramBadge:")
    badge_end = badge.index("/// `.compact`")
    production = "\n".join([
        verification, policy,
        "public extension Peer {\n" + peer_getters + "\n}",
        "public extension EnginePeer {\n" + engine_getters + "\n}",
        badge[badge_start:badge_end],
    ])
    template = Path(__file__).with_name("fixtures.swift").read_text(encoding="utf-8")
    assert template.count("// PRODUCTION") == 1

    # Any raw UI access must be an explicit trust/action/model-copy exception.
    exceptions = {
        "submodules/TelegramUI/Sources/ChatController.swift",
        "submodules/TelegramUI/Sources/Chat/ChatControllerOpenWebApp.swift",
        "submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift",
        "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift",
        "submodules/TelegramCallsUI/Sources/PresentationGroupCall.swift",
        "submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewController.swift",
        "submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewPeerContentNode.swift",
        "submodules/WebUI/Sources/WebAppTitleView.swift",
        "submodules/WebUI/Sources/FullscreenControlsComponent.swift",
        "submodules/ImportStickerPackUI/Sources/StickerPackPreviewGridItem.swift",
        "submodules/ImportStickerPackUI/Sources/ImportStickerPackControllerNode.swift",
    }
    for file in (ROOT / "submodules").rglob("*.swift"):
        relative = file.relative_to(ROOT).as_posix()
        if relative.startswith(("submodules/TelegramCore/", "submodules/TelegramApi/")) or "/Tests/" in relative:
            continue
        source = file.read_text(encoding="utf-8")
        if ".isVerified" in source:
            assert relative in exceptions, f"Unfiltered UI verification: {relative}"
        for line in source.splitlines():
            if "= peer.verificationIconFileId {" in line or "= item.peer.verificationIconFileId {" in line:
                assert relative.endswith("PeerInfoScreen.swift"), f"Unfiltered third-party icon: {relative}"

    profile = (ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift").read_text(encoding="utf-8")
    assert profile.count("DonutgramVerificationDisplay.verification((data.cachedData as?") == 2
    panels = (ROOT / "submodules/TelegramUI/Sources/ChatInterfaceTitlePanelNodes.swift").read_text(encoding="utf-8")
    assert "if !DonutgramVerificationDisplay.isHidden, let _ = chatPresentationInterfaceState.peerVerification" in panels
    card = (ROOT / "submodules/TelegramUI/Components/Chat/ChatUserInfoItem/Sources/ChatUserInfoItem.swift").read_text(encoding="utf-8")
    assert "DonutgramVerificationDisplay.verification(item.verification)" in card
    appearance = (ROOT / "Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift").read_text(encoding="utf-8")
    assert '"hideVerification", "Скрыть верификацию", s.hideVerification' in appearance, "Settings entry is missing"
    assert 'case "hideVerification": s.hideVerification = value' in appearance, "Settings entry is not wired to the flag"
    assert "hideVerification" not in badge
    for name in ["ChatTitleComponent.swift", "ChatTitleView.swift"]:
        source = (ROOT / "submodules/TelegramUI/Components/ChatTitleView/Sources" / name).read_text(encoding="utf-8")
        assert "donutgramBadge(peerId: peer.id)" in source
        assert "donutgramBadgeContent(" in source
    source = (ROOT / "submodules/ChatListUI/Sources/Node/ChatListItem.swift").read_text(encoding="utf-8")
    assert source.count("if let badge = donutgramBadge(peerId: peer.id)") == 2
    return template.replace("// PRODUCTION", production)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    source = harness()
    if args.source_only:
        print("Verification getter extraction, UI coverage and Donutgram badge source checks passed; Swift execution was not run.")
        return
    swift = shutil.which("swiftc")
    if not swift:
        raise SystemExit("swiftc is required; run on macOS with Xcode.")
    with tempfile.TemporaryDirectory(prefix="donutgram-verification-") as temporary:
        directory = Path(temporary)
        settings = list((ROOT / "Donutgram/DGSimpleSettings/Sources").glob("*.swift"))
        subprocess.run([swift, "-warnings-as-errors", "-emit-library", "-emit-module", "-module-name", "DGSimpleSettings",
                        *map(str, settings), "-o", str(directory / "libDGSimpleSettings.dylib")], cwd=directory, check=True)
        main_file = directory / "main.swift"
        executable = directory / "verification-tests"
        main_file.write_text(source, encoding="utf-8")
        subprocess.run([swift, "-warnings-as-errors", str(main_file), "-I", str(directory), "-L", str(directory),
                        "-lDGSimpleSettings", "-Xlinker", "-rpath", "-Xlinker", str(directory), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        subprocess.run([str(executable), "write-setting"], check=True)
        subprocess.run([str(executable), "read-setting"], check=True)
        subprocess.run([str(executable), "read-restored"], check=True)
        # Parse every changed Swift file, including complete UI files.
        changed = subprocess.check_output(["git", "diff", "--name-only", "HEAD^1", "HEAD"], cwd=ROOT, text=True).splitlines()
        for file in changed:
            if file.endswith(".swift"):
                subprocess.run([swift, "-frontend", "-parse", str(ROOT / file)], check=True)
        print("Changed Swift source parsing passed.")


if __name__ == "__main__":
    main()
