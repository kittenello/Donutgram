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
    defaults.synchronize()
    print("settings behavior checks passed")
} else if mode == "read" {
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
