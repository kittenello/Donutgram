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
for mask in 0 ..< 32 {
    let flags = TelegramChatBannedRightsFlags(rawValue: mask)
    let peers: [Peer] = [TelegramChannel(flags), TelegramGroup(flags)]
    for peer in peers {
        let canUseMedia = mask & 1 != 0 && mask & 24 == 0
        check(donutgramCanSendStickerAsMedia(peer: peer) == (canUseMedia && mask & 6 != 6), "keyboard permissions: \(mask)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: photo) == (canUseMedia && mask & 2 == 0), "photo permissions: \(mask)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: lottie) == (canUseMedia && mask & 4 == 0), "lottie permissions: \(mask)")
        check(donutgramCanSendStickerAsMedia(peer: peer, file: webm) == (canUseMedia && mask & 4 == 0), "webm permissions: \(mask)")
        check(!donutgramCanSendStickerAsMedia(peer: peer, file: document), "documents stay documents")
    }
}
check(!donutgramCanSendStickerAsMedia(peer: nil), "unknown peers remain restricted")
testSettings.stickerUnlock = false
check(!donutgramCanSendStickerAsMedia(peer: TelegramChannel(.banSendStickers), file: webm), "disabling restores normal sending")
print("sticker media permission checks passed")
