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
    for enabled in [false, true] {
        settings.disableMediaAutoplay = enabled
        for mask in 0 ... 3 {
            settings.disabledAutoplayMediaTypes = mask
            check(settings.shouldStopAfterMedia(isRoundVideo: false) == (enabled && mask & 1 != 0), "stop after a completed voice message")
            check(settings.shouldStopAfterMedia(isRoundVideo: true) == (enabled && mask & 2 != 0), "stop after a completed round video")
        }
    }
    for hidden in [false, true] {
        for pinned in [false, true] {
            settings.hideBotAutomation = hidden
            settings.showPinnedMessagesWithBot = pinned
            for hasPin in [false, true] {
                check(settings.shouldShowBotAutomation(hasPinnedMessage: hasPin) == (!hidden && !(pinned && hasPin)), "bot/pin precedence")
            }
        }
    }
    settings.hidePaidReactions = true
    settings.hideBirthdayNotifications = true
    settings.hideViaBot = true
    settings.hideBotAutomation = true
    settings.showPinnedMessagesWithBot = true
    settings.removeLinkPreviews = true
    settings.disabledAutoplayMediaTypes = 1
    settings.disableMediaAutoplay = false
    check(settings.disabledAutoplayMediaTypes == 1, "turning the stop switch off must preserve its selection")
    check(!settings.shouldStopAfterMedia(isRoundVideo: false) && !settings.shouldStopAfterMedia(isRoundVideo: true), "switch off restores Telegram autoplay for both types")
    settings.disableMediaAutoplay = true
    defaults.synchronize()
    print("settings behavior checks passed")
} else if mode == "read" {
    check(settings.hidePaidReactions && settings.hideBirthdayNotifications && settings.hideViaBot, "visibility preferences must survive process restart")
    check(settings.hideBotAutomation && settings.showPinnedMessagesWithBot && settings.removeLinkPreviews, "bot/link preferences must survive process restart")
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
