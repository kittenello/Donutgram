import Foundation

struct TelegramChatBannedRightsFlags: OptionSet {
    let rawValue: Int
    static let banSendStickers = Self(rawValue: 1)
    static let banSendPhotos = Self(rawValue: 2)
    static let banSendVideos = Self(rawValue: 4)
    static let banSendMedia = Self(rawValue: 8)
    static let banReadMessages = Self(rawValue: 16)
}

protocol Peer {}

final class TelegramChannel: Peer {
    let banned: TelegramChatBannedRightsFlags
    init(_ banned: TelegramChatBannedRightsFlags) { self.banned = banned }
    func hasBannedPermission(_ permission: TelegramChatBannedRightsFlags) -> (Int32, Bool)? {
        return self.banned.contains(permission) ? (Int32.max, true) : nil
    }
}

final class TelegramGroup: Peer {
    let banned: TelegramChatBannedRightsFlags
    init(_ banned: TelegramChatBannedRightsFlags) { self.banned = banned }
    func hasBannedPermission(_ permission: TelegramChatBannedRightsFlags) -> Bool {
        return self.banned.contains(permission)
    }
}

final class TelegramMediaFile {
    let isSticker: Bool
    let isAnimatedSticker: Bool
    let isVideoSticker: Bool
    init(sticker: Bool = true, animated: Bool = false, video: Bool = false) {
        self.isSticker = sticker
        self.isAnimatedSticker = animated
        self.isVideoSticker = video
    }
}

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}

let suite = "donutgram-sticker-media-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
let testSettings = DGSimpleSettings(defaults: defaults)
defer { defaults.removePersistentDomain(forName: suite) }
let photo = TelegramMediaFile()
let lottie = TelegramMediaFile(animated: true)
let webm = TelegramMediaFile(video: true)
let document = TelegramMediaFile(sticker: false)
check(!donutgramCanSendStickerAsMedia(peer: TelegramGroup(.banSendStickers)), "disabled by default")
testSettings.stickerUnlock = true

/// What a chat lets through, written out by hand instead of with the policy's own formula.
struct Scenario {
    let name: String
    let banned: TelegramChatBannedRightsFlags
    /// The sticker panel opens.
    let panel: Bool
    let staticSticker: Bool
    let animatedSticker: Bool
}

let scenarios: [Scenario] = [
    Scenario(name: "stickers allowed", banned: [], panel: false, staticSticker: false, animatedSticker: false),
    Scenario(name: "photos banned, stickers allowed", banned: [.banSendPhotos], panel: false, staticSticker: false, animatedSticker: false),
    Scenario(name: "only stickers banned", banned: [.banSendStickers], panel: true, staticSticker: true, animatedSticker: true),
    Scenario(name: "stickers and photos banned", banned: [.banSendStickers, .banSendPhotos], panel: true, staticSticker: true, animatedSticker: true),
    Scenario(name: "stickers and videos banned", banned: [.banSendStickers, .banSendVideos], panel: false, staticSticker: false, animatedSticker: false),
    Scenario(name: "stickers, photos and videos banned", banned: [.banSendStickers, .banSendPhotos, .banSendVideos], panel: false, staticSticker: false, animatedSticker: false),
    Scenario(name: "all media banned", banned: [.banSendStickers, .banSendMedia], panel: false, staticSticker: false, animatedSticker: false),
    Scenario(name: "removed from the chat", banned: [.banSendStickers, .banReadMessages], panel: false, staticSticker: false, animatedSticker: false)
]
for scenario in scenarios {
    let peers: [Peer] = [TelegramChannel(scenario.banned), TelegramGroup(scenario.banned)]
    for peer in peers {
        check(donutgramCanSendStickerAsMedia(peer: peer) == scenario.panel, "sticker panel: \(scenario.name)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: photo) == scenario.staticSticker, "static sticker: \(scenario.name)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: lottie) == scenario.animatedSticker, "lottie sticker: \(scenario.name)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: webm) == scenario.animatedSticker, "webm sticker: \(scenario.name)")
        check(!donutgramCanSendStickerAsMedia(peer: peer, file: document), "documents stay documents: \(scenario.name)")
    }
}
check(!donutgramCanSendStickerAsMedia(peer: nil), "unknown peers remain restricted")
testSettings.stickerUnlock = false
check(!donutgramCanSendStickerAsMedia(peer: TelegramChannel(.banSendStickers), file: webm), "disabling restores normal sending")
print("sticker media permission checks passed")


// Model the overlay's contract: dismissing before presentation finishes has no effect.
final class ViewController {
    var hasAppeared = false
    var dismissCount = 0
    var dismissedBeforeAppearance = false

    func dismiss() {
        if self.hasAppeared {
            self.dismissCount += 1
        } else {
            self.dismissedBeforeAppearance = true
        }
    }
}

func checkStickerMediaProgress() {
    for finishBeforePresentation in [false, true] {
        let progress = DonutgramStickerMediaProgress()
        let overlay = ViewController()
        var completePresentation: (() -> Void)?
        progress.show(overlay, present: { _, completion in
            completePresentation = completion
        })
        if finishBeforePresentation {
            progress.finish()
            check(overlay.dismissCount == 0, "wait for a pending presentation before dismissing")
        }
        overlay.hasAppeared = true
        completePresentation?()
        if !finishBeforePresentation {
            progress.finish()
        }
        progress.finish()
        check(overlay.dismissCount == 1, "success, failure or cancellation dismisses the overlay exactly once")
        check(!overlay.dismissedBeforeAppearance, "never dismiss an overlay before it appears")
    }

    let fast = DonutgramStickerMediaProgress()
    fast.finish()
    var presented = false
    fast.show(ViewController(), present: { _, _ in presented = true })
    check(!presented, "a cached static sticker that finishes before the delay shows no late spinner")
}
checkStickerMediaProgress()
print("sticker conversion progress lifecycle checks passed")
