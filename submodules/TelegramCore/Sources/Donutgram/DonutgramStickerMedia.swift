import Foundation
import Postbox
import DGSimpleSettings

public func donutgramCanSendStickerAsMedia(peer: Peer?, file: TelegramMediaFile? = nil) -> Bool {
    guard DGSimpleSettings.shared.stickerUnlock else {
        return false
    }
    let isBanned: (TelegramChatBannedRightsFlags) -> Bool
    if let channel = peer as? TelegramChannel {
        isBanned = { channel.hasBannedPermission($0) != nil }
    } else if let group = peer as? TelegramGroup {
        isBanned = { group.hasBannedPermission($0) }
    } else {
        return false
    }
    guard isBanned(.banSendStickers), !isBanned(.banSendMedia), !isBanned(.banReadMessages) else {
        return false
    }
    if let file {
        guard file.isSticker else {
            return false
        }
    }
    return !isBanned(.banSendVideos)
}
