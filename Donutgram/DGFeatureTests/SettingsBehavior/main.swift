import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

let mode = CommandLine.arguments[1]
let suiteName = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suiteName)!
let settings = DGSimpleSettings(defaults: defaults)

if mode == "write" {
    defaults.removePersistentDomain(forName: suiteName)
    check(!settings.disableMediaAutoplay && settings.disabledAutoplayMediaTypes == 3, "existing sequential playback must remain enabled by default")
    check(!settings.hidePaidReactions && !settings.hideViaBot && !settings.hideBirthdayNotifications, "hiding must be opt-in")
    check(!settings.hideServiceMessages && !settings.confirmReactionsInUnjoinedChats && !settings.confirmTelegramLinks && !settings.confirmChatPreviewEntry, "safety switches must be opt-in")
    check(!settings.disableStoryCameraSwipe, "the swipe to the story camera must stay on by default")
    check(!settings.disableGiftStarsRedirect, "gift sales open Stars by default")
    check(!settings.keepBannedChats, "keeping banned chats is opt-in")
    check(settings.visualLabel(accountId: 1001) == .none, "visual badge is disabled by default")
    check(settings.visualLabel(accountId: 1002) == .none, "another account starts without a badge")
    settings.setVisualLabel(.scam, accountId: 1001)
    check(settings.visualLabel(accountId: 1001) == .scam, "badge applies to selected account")
    check(settings.visualLabel(accountId: 1002) == .none, "badge never leaks between accounts")
    settings.setVisualLabel(.bot, accountId: 1002)
    check(settings.jumpToStartInChatMenu, "«В начало чата» is in the avatar menu by default")
    for enabled in [false, true] {
        settings.disableMediaAutoplay = enabled
        for mask in 0 ... 3 {
            settings.disabledAutoplayMediaTypes = mask
            check(settings.shouldStopAfterMedia(isRoundVideo: false) == (enabled && mask & 1 != 0), "stop after a completed voice message")
            check(settings.shouldStopAfterMedia(isRoundVideo: true) == (enabled && mask & 2 != 0), "stop after a completed round video")
        }
    }
    for hidden in [false, true] {
        settings.hideBotAutomation = hidden
        check(settings.shouldShowBotAutomation() == !hidden, "the bot automation panel follows its own switch")
    }
    settings.hidePaidReactions = true
    settings.hideBirthdayNotifications = true
    settings.disableStoryCameraSwipe = true
    settings.disableGiftStarsRedirect = true
    settings.keepBannedChats = true
    settings.hideViaBot = true
    settings.hideBotAutomation = true
    settings.removeLinkPreviews = true
    settings.hideServiceMessages = true
    settings.confirmReactionsInUnjoinedChats = true
    settings.confirmTelegramLinks = true
    settings.confirmChatPreviewEntry = true
    settings.disabledAutoplayMediaTypes = 1
    settings.disableMediaAutoplay = false
    check(settings.disabledAutoplayMediaTypes == 1, "turning the stop switch off must preserve its selection")
    check(!settings.shouldStopAfterMedia(isRoundVideo: false) && !settings.shouldStopAfterMedia(isRoundVideo: true), "switch off restores Telegram autoplay for both types")
    settings.disableMediaAutoplay = true
    settings.jumpToStartInChatMenu = false
    let packData = Data([1, 2, 3])
    settings.setAnonymousStickerPackData(packData, accountId: 1001, fileId: 5001)
    check(settings.anonymousStickerPackData(accountId: 1001, fileId: 5001) == packData, "sticker pack data is saved")
    check(settings.anonymousStickerPackData(accountId: 1002, fileId: 5001) == nil, "sticker packs are isolated by account")
    check(settings.anonymousStickerPackData(accountId: 1001, fileId: 5002) == nil, "sticker packs are isolated by file")
    let packLimit = Int64(DGSimpleSettings.anonymousStickerPackLimit)
    for fileId in 1 ... packLimit {
        settings.setAnonymousStickerPackData(Data([4]), accountId: 1003, fileId: fileId)
    }
    settings.setAnonymousStickerPackData(Data([5]), accountId: 1003, fileId: 1)
    settings.setAnonymousStickerPackData(Data([6]), accountId: 1003, fileId: packLimit + 1)
    check(settings.anonymousStickerPackData(accountId: 1003, fileId: 2) == nil, "past the limit the oldest sticker pack is dropped")
    check(settings.anonymousStickerPackData(accountId: 1003, fileId: 1) == Data([5]), "saving a sticker pack again makes it the newest")
    check(settings.anonymousStickerPackData(accountId: 1003, fileId: 3) == Data([4]) && settings.anonymousStickerPackData(accountId: 1003, fileId: packLimit + 1) == Data([6]), "the newer sticker packs stay")
    check(!settings.hideBlockedMessages && settings.hiddenBlockedPeerIds.isEmpty && !settings.hasShadowBans, "hiding blocked peers is opt-in")
    settings.setBlockedPeerIds([7001, 7002], accountId: 1001)
    settings.setPeerBlocked(true, peerId: 7101, accountId: 1002)
    check(settings.blockedPeerIds(accountId: 1001) == [7001, 7002] && settings.blockedPeerIds(accountId: 1002) == [7101], "blocked peers are kept per account")
    check(settings.hiddenBlockedPeerIds.isEmpty, "nothing is hidden while the switch is off")
    settings.hideBlockedMessages = true
    check(settings.hiddenBlockedPeerIds.isEmpty, "nothing is hidden before the shown account is known")
    settings.setBlockedPeersShownAccountId(1001)
    check(settings.hiddenBlockedPeerIds == [7001, 7002] && settings.hasShadowBans, "the shown account's blocked peers are hidden")
    settings.setPeerBlocked(false, peerId: 7002, accountId: 1001)
    settings.setPeerBlocked(true, peerId: 7003, accountId: 1001)
    check(settings.hiddenBlockedPeerIds == [7001, 7003], "a block and an unblock apply at once")
    settings.setBlockedPeersShownAccountId(1002)
    check(settings.hiddenBlockedPeerIds == [7101], "another shown account hides its own blocked peers")
    defaults.synchronize()
    print("settings behavior checks passed")
} else if mode == "read" {
    check(settings.anonymousStickerPackData(accountId: 1001, fileId: 5001) == Data([1, 2, 3]), "sticker pack data survives process restart")
    check(settings.anonymousStickerPackData(accountId: 1003, fileId: Int64(DGSimpleSettings.anonymousStickerPackLimit) + 1) == Data([6]), "the newest sticker packs survive process restart")
    check(settings.hideBlockedMessages, "hiding blocked peers must survive process restart")
    check(settings.blockedPeerIds(accountId: 1001) == [7001, 7003] && settings.blockedPeerIds(accountId: 1002) == [7101], "blocked peers must survive process restart")
    check(settings.hiddenBlockedPeerIds.isEmpty, "each launch sets the shown account again")
    check(settings.hidePaidReactions && settings.hideBirthdayNotifications && settings.hideViaBot, "visibility preferences must survive process restart")
    check(settings.hideBotAutomation && settings.removeLinkPreviews, "bot/link preferences must survive process restart")
    check(settings.hideServiceMessages && settings.confirmReactionsInUnjoinedChats && settings.confirmTelegramLinks && settings.confirmChatPreviewEntry, "safety preferences must survive process restart")
    check(settings.disableStoryCameraSwipe, "turning off the swipe to the story camera must survive process restart")
    check(settings.disableGiftStarsRedirect, "disabling the gift Stars redirect must survive process restart")
    check(settings.keepBannedChats, "keeping banned chats must survive process restart")
    check(settings.visualLabel(accountId: 1001) == .scam, "account badge must persist across restart")
    check(settings.visualLabel(accountId: 1002) == .bot, "second account badge must persist independently")
    settings.setVisualLabel(.none, accountId: 1001)
    check(settings.visualLabel(accountId: 1001) == .none, "visual badge can be disabled")
    check(settings.visualLabel(accountId: 1002) == .bot, "disabling badge does not affect other account")
    settings.disableGiftStarsRedirect = false
    check(!settings.disableGiftStarsRedirect, "the gift Stars redirect can be enabled again")
    check(!settings.jumpToStartInChatMenu, "a hidden «В начало чата» stays hidden after a restart")
    settings.jumpToStartInChatMenu = true
    check(settings.jumpToStartInChatMenu, "«В начало чата» can be shown again")
    check(settings.disableMediaAutoplay && settings.disabledAutoplayMediaTypes == 1, "autoplay preferences must survive process restart")
    check(settings.shouldStopAfterMedia(isRoundVideo: false) && !settings.shouldStopAfterMedia(isRoundVideo: true), "persisted selection stops after voice but allows continuation after round videos")
    settings.disableMediaAutoplay = false
    check(!settings.shouldStopAfterMedia(isRoundVideo: false) && !settings.shouldStopAfterMedia(isRoundVideo: true), "switch off restores normal autoplay after a restart")
    settings.disableMediaAutoplay = true
    check(settings.shouldStopAfterMedia(isRoundVideo: false) && !settings.shouldStopAfterMedia(isRoundVideo: true), "re-enabling the stop switch restores its selection")
    defaults.removePersistentDomain(forName: suiteName)
    print("settings process-restart checks passed")
} else {
    fatalError("unknown check mode")
}
