"""Compile production extractors/archive policy against fixtures on a macOS Swift runner."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def without_imports(text):
    return "\n".join(line for line in text.splitlines() if not line.startswith("import "))


def prepare(directory):
    # Check integration in addition to executing the policy itself.
    peers = source("submodules/TelegramCore/Sources/UpdatePeers.swift")
    assert "donutgramUpdateBannedChat(transaction: transaction, previous: previous, updated: updated)" in peers
    assert peers.index("donutgramUpdateBannedChat(") < peers.index("switch peerId.namespace")
    assert "return update(previous, donutgramPreservedBannedPeer(previous: previous, updated: updated))" in peers
    reset = source("submodules/TelegramCore/Sources/State/ResetState.swift")
    assert "preservedBannedChats.append" in reset and "inclusion: inclusion" in reset
    holes = source("submodules/TelegramCore/Sources/State/Holes.swift")
    assert "donutgramIsPreservedBannedChat(transaction: transaction, peerId: archivedPeerId)" in holes
    # Every pinned list from the server leaves out a kept chat: reloading the chat list, a full reset, a pins sync.
    keep_pins = "itemIds: donutgramKeepingPinnedBannedChats(transaction: transaction, currentItemIds: transaction.getPinnedItemIds(groupId: {}), itemIds: replacePinnedItemIds.map(PinnedItemId.peer))"
    assert keep_pins.format("groupId") in holes and keep_pins.format(".root") in reset
    pins = source("submodules/TelegramCore/Sources/State/ManagedSynchronizePinnedChatsOperations.swift")
    assert "transaction.setPinnedItemIds(groupId: groupId, itemIds: donutgramKeepingPinnedBannedChats(transaction: transaction, currentItemIds: localItemIds, itemIds: serverItemIds))" in pins
    assert "if remoteItemIds == serverItemIds {" in pins and "for itemId in serverItemIds {" in pins and "setPinnedItemIds(groupId: groupId, itemIds: resultingItemIds)" not in pins
    cached = source("submodules/TelegramCore/Sources/TelegramEngine/Peers/UpdateCachedPeerData.swift")
    # getFullChannel fails in a channel the account is banned from; a kept chat must not lose its pin and migration link,
    # but drops a call that was on at the ban: nothing tells the account it ended.
    failed = cached.split("let isPreservedBannedChat = donutgramIsPreservedBannedChat(transaction: transaction, peerId: peerId)", 1)[1]
    keep = "if isPreservedBannedChat, let current {\n                                    if let current = current as? CachedChannelData {\n                                        return current.withUpdatedActiveCall(nil)\n                                    }\n                                    return current\n"
    assert failed.index(keep) < failed.index("withUpdatedIsNotAccessible(true)")
    sync = source("submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift")
    poll = sync.split("private func pollChannel(", 1)[1]
    assert poll.index("if donutgramPeerIsBanned(peer)") < poll.index("network.request(")
    # A kept chat is a channel the account is not in (kicked), and such a channel keeps no read state since 13.1: it is
    # still read like any chat, and the synchronizer confirms that read without a request.
    read = source("submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift")
    guards = [line.strip() for line in read.splitlines() if line.strip().startswith("guard peerKeepsReadState(")]
    assert len(guards) == 2 and all("|| donutgramIsPreservedBannedChat(transaction: transaction, peerId: " in line for line in guards), guards
    read_sync = source("submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift")
    assert "if !keepsReadState {\n            return confirmSynchronized(postbox: postbox, peerId: peerId)" in read_sync
    panels = source("submodules/TelegramUI/Sources/ChatInterfaceStateInputPanels.swift")
    assert "case .kicked:" in panels and "case .Removed, .Left:" in panels
    content = source("submodules/TelegramUI/Sources/ChatControllerContentData.swift")
    assert "shouldDismiss = false\n                        strongSelf.state.performDismissAction = .bannedChat" in content
    # Only a chat that was kept loses the "no access" screen and gets the alert; other banned chats behave as in Telegram.
    preserved = "donutgramIsPreservedBannedChat(peer: peerView.peers[peerView.peerId], groupId: peerView.groupId)"
    assert content.count("isNotAccessible = cachedChannelData.isNotAccessible && !" + preserved) == 2
    assert "let isPreservedBannedChat = " + preserved + "\n                    if isPreservedBannedChat, shouldDismiss" in content
    assert "keepBannedChats" not in content
    ui = source("submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift")
    alert = ui.split("case .bannedChat:", 1)[1].split("self.updatePreloadNextChatPeerId", 1)[0]
    assert "self.presentBannedChatAlertIfNeeded()" in alert and "self.dismiss()" not in alert
    # The alert waits for the chat to be on screen: a controller without a window drops what it presents.
    presenter = ui.split("func presentBannedChatAlertIfNeeded()", 1)[1].split("\n    }\n", 1)[0]
    assert "guard self.didAppear" in presenter and "Common_OK" in presenter
    assert presenter.index("self.didHandlePerformDismissAction = true") < presenter.index("self.present(")
    controller = source("submodules/TelegramUI/Sources/ChatController.swift")
    appear = controller.split("override public func viewDidAppear(", 1)[1]
    assert appear.index("self.didAppear = true") < appear.index("self.presentBannedChatAlertIfNeeded()") < appear.index("\n    }\n")
    node = source("submodules/TelegramUI/Sources/ChatControllerNode.swift")
    assert "} else if chatPresentationInterfaceState.isNotAccessible {" in node and "donutgram" not in node.split("var restrictionText: String?", 1)[1][:2000]
    job = source("Donutgram/DGLinkDownloader/Sources/DGLinkDownloadJob.swift")
    assert "!batch.failed" in job and "DGTikTokExtractor.run(" in job
    assert "failure: failed" in job and "self.isCancelRequested" in job.split("func downloadTikTok(", 1)[1]
    assert "directory.appendingPathComponent(\"source-\\(index)\")" in job
    # A failed attempt leaves nothing behind: its folder goes before the next source is tried, photos included.
    attempt = job.split("func downloadTikTok(", 1)[1].split("\n    }\n", 1)[0]
    assert attempt.index("try? FileManager.default.removeItem(at: directory)") < attempt.index("failure(error)")
    assert "source.deletingLastPathComponent().appendingPathComponent(\"photo-\\(index).jpg\")" in job
    # Photos are made as they arrive, six downloads at a time (TikTok's photo CDN is HTTP/2); one that cannot be made
    # fails its attempt like a failed download, so TikWM is still tried.
    assert "self.download(items, limit: 6, prepare: { index, source in" in job
    assert "guard let prepared = prepare(index, url) else {\n                            fail(.processingFailed)" in job
    # So a carousel's job ends right after its last download: from then on the toast shows processing, and it closes on
    # the job's last status rather than on the frame its timer drew last.
    arrived = job.split("case let .success(url):", 1)[1].split("\n                    }\n", 1)[0]
    assert arrived.index("if batch.remaining == 1 {") < arrived.index("self.report(.processing)") < arrived.index("prepare(index, url)")
    toast = source("submodules/TelegramUI/Sources/ChatController+DonutgramLinkDownload.swift").split("func finish() {", 1)[1].split("\n    }\n", 1)[0]
    assert toast.index("self.render()") < toast.index("self.controller?.dismiss()")
    # TikWM sees the post and the user's IP: the downloads page says so.
    downloads = source("Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift").split("func dgDownloadsSettingsController(", 1)[1].split("\n}\n", 1)[0]
    assert "tikwm.com" in downloads

    imports = "import Foundation\nimport CoreFoundation\n"
    tik = imports + "import CryptoKit\n" + "\n".join(without_imports(source("Donutgram/DGLinkDownloader/Sources/" + f)) for f in [
        "DGLinkDownloadError.swift", "DGLinkDownloadModels.swift", "DGLinkDownloadLink.swift", "DGTikTokExtractor.swift"
    ])
    (directory / "tiktok").mkdir()
    (directory / "tiktok" / "main.swift").write_text(tik + "\n" + (HERE / "tiktok.swift").read_text(encoding="utf-8"), encoding="utf-8")

    archive = without_imports(source("submodules/TelegramCore/Sources/Donutgram/DonutgramBannedChats.swift"))
    # The same exclusion function used by sync, tested with real archive policy.
    exclusion = peers[peers.index("func isPeerHiddenByCollapsedCommunity"):peers.index("func updatePeerChatInclusionWithMinTimestamp")]
    fixture, cases = (HERE / "banned.swift").read_text(encoding="utf-8").split("// TEST CASES", 1)
    (directory / "banned").mkdir()
    (directory / "banned" / "main.swift").write_text("\n\n".join((imports, fixture, archive, exclusion, cases)), encoding="utf-8")
    fetcher = imports + "\n".join(without_imports(source("Donutgram/DGLinkDownloader/Sources/" + f)) for f in [
        "DGLinkDownloadError.swift", "DGMediaFetcher.swift"
    ])
    (directory / "fetcher").mkdir()
    (directory / "fetcher" / "main.swift").write_text(fetcher + "\n" + (HERE / "fetcher.swift").read_text(encoding="utf-8"), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="dg-tiktok-ban-") as temporary:
        directory = Path(temporary)
        prepare(directory)
        if args.prepare_only:
            print("fixture generation and integration checks passed; Swift execution skipped")
        else:
            compiler = shutil.which("swiftc")
            if compiler is None:
                raise SystemExit("swiftc required to execute behavioral checks")
            for case in ["tiktok", "banned"]:
                executable = directory / case / "check"
                subprocess.run([compiler, "-warnings-as-errors", str(directory / case / "main.swift"), "-o", str(executable)], check=True)
                subprocess.run([str(executable)], check=True)
            requests = []
            cookie_headers = []
            heads = []

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    requests.append(self.path)
                    if self.path == "/echo-cookie":
                        cookie_headers.append(self.headers.get("Cookie") or "")
                    status = {"/denied": 403, "/missing": 404, "/gone": 410, "/landing": 404}.get(self.path, 200)
                    payload = b"A" * 8192 if status == 200 else b"denied"
                    self.send_response(status)
                    if self.path == "/set-cookie":
                        self.send_header("Set-Cookie", "page=1; Path=/")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    try:
                        self.wfile.write(payload)
                    except ConnectionError:
                        pass

                def do_HEAD(self):
                    heads.append((self.path, self.headers.get("User-Agent")))
                    if self.path == "/redirect":
                        self.send_response(302)
                        self.send_header("Location", "/landing")
                    else:
                        self.send_response(404)
                    self.send_header("Content-Length", "0")
                    self.end_headers()

                def log_message(self, *args):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                executable = directory / "fetcher" / "check"
                subprocess.run([compiler, "-warnings-as-errors", str(directory / "fetcher" / "main.swift"), "-o", str(executable)], check=True)
                subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}"], check=True)
                assert "/unexpected" not in requests and "/cancelled" not in requests, requests
                assert requests.count("/denied") == 3 and requests.count("/media") == 2, requests
                # A cookie set from code joins the page's own cookies for the next request only.
                assert len(cookie_headers) == 2, cookie_headers
                assert "page=1" in cookie_headers[0] and "answer=YWJj=" in cookie_headers[0], cookie_headers
                assert "page=1" in cookie_headers[1] and "answer" not in cookie_headers[1], cookie_headers
                # The short link's second try is a HEAD request; only its final address matters.
                assert heads and heads[0][0] == "/redirect", heads
            finally:
                server.shutdown()
                server.server_close()
