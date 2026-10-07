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
    check(settings.autoplayMedia && settings.autoplayMediaTypes == 3, "existing sequential playback must remain enabled by default")
    check(!settings.hidePaidReactions && !settings.hideViaBot && !settings.hideBirthdayNotifications, "hiding must be opt-in")
    for enabled in [false, true] {
        settings.autoplayMedia = enabled
        for mask in 0 ... 3 {
            settings.autoplayMediaTypes = mask
            check(settings.shouldAutoplayMedia(isRoundVideo: false) == (enabled && mask & 1 != 0), "voice target selection")
            check(settings.shouldAutoplayMedia(isRoundVideo: true) == (enabled && mask & 2 != 0), "round-video target selection")
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
    settings.autoplayMediaTypes = 1
    settings.autoplayMedia = false
    check(settings.autoplayMediaTypes == 1, "disabling autoplay must preserve its selection")
    defaults.synchronize()
    print("settings behavior checks passed")
} else if mode == "read" {
    check(settings.hidePaidReactions && settings.hideBirthdayNotifications && settings.hideViaBot, "visibility preferences must survive process restart")
    check(settings.hideBotAutomation && settings.showPinnedMessagesWithBot && settings.removeLinkPreviews, "bot/link preferences must survive process restart")
    check(!settings.autoplayMedia && settings.autoplayMediaTypes == 1, "autoplay preferences must survive process restart")
    settings.autoplayMedia = true
    check(settings.shouldAutoplayMedia(isRoundVideo: false) && !settings.shouldAutoplayMedia(isRoundVideo: true), "re-enabling autoplay must restore its selection")
    defaults.removePersistentDomain(forName: suiteName)
    print("settings process-restart checks passed")
} else {
    fatalError("unknown check mode")
}
