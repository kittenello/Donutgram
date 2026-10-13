import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
final class TelegramMediaFile {
    let isSticker: Bool
    init(isSticker: Bool) { self.isSticker = isSticker }
}
struct FixtureMessage { let media: [Any] }
struct FixtureArguments {
    struct Strings { let Message_Sticker = "стикер" }
    let strings = Strings()
}
func replyDescription(isMediaValue: Bool, message: FixtureMessage, textStringValue: NSAttributedString) -> NSAttributedString {
    let arguments = FixtureArguments()
    let textString: NSAttributedString
    // PRODUCTION_DESCRIPTION
    return textString
}

let mode = CommandLine.arguments[1]
let suite = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
let settings = DGSimpleSettings(defaults: defaults)
if mode == "write" {
    defaults.removePersistentDomain(forName: suite)
    check(settings.stickerReplyOptions == 7 && !settings.hidePremiumReplyEmoji, "new controls must preserve defaults")
    for options in 0 ... 7 {
        settings.stickerReplyOptions = options
        check(settings.hideStickerReplyColors == (options & 1 == 0), "old color preference respected")
        check(settings.hideStickerReplyEmoji == (options & 2 == 0), "old emoji preference respected")
        check(settings.hideStickerReplyBackground == (options & 4 == 0), "old background preference respected")
        for hidden in [false, true] {
            settings.stickerReplyOptions = options
            settings.hideStickerReplyColors = hidden
            check(settings.stickerReplyOptions == (hidden ? options & ~1 : options | 1), "color toggle preserves other choices")
            settings.stickerReplyOptions = options
            settings.hideStickerReplyEmoji = hidden
            check(settings.stickerReplyOptions == (hidden ? options & ~2 : options | 2), "emoji toggle preserves other choices")
            settings.stickerReplyOptions = options
            settings.hideStickerReplyBackground = hidden
            check(settings.stickerReplyOptions == (hidden ? options & ~4 : options | 4), "background toggle preserves other choices")
            settings.stickerReplyOptions = options
            settings.hidePremiumReplyEmoji = hidden
            check(settings.replyDecorationOptions(isSticker: true) == (hidden ? options & ~2 : options), "premium switch combines with sticker choices")
            check(settings.replyDecorationOptions(isSticker: false) == (hidden ? 5 : 7), "ordinary replies hide only the premium decoration")
            check(settings.stickerReplyOptions == options, "premium switch must preserve sticker settings")
        }
    }
    settings.commaAfterMention = false
    check(settings.mentionSuffix(isBot: false) == " ", "default mention suffix")
    settings.commaAfterMention = true
    check(settings.mentionSuffix(isBot: false) == ", " && settings.mentionSuffix(isBot: true) == " ", "real mention suffix handles users and bots")

    // Every switch affecting the message preview must invalidate its list row.
    let paths: [ReferenceWritableKeyPath<DGSimpleSettings, Bool>] = [\.removeMessageTails, \.showMessageSeconds, \.disableColoredReplies, \.editedIcon, \.hidePremiumReplyEmoji, \.commaAfterMention, \.mentionAvatars, \.showForwardDate]
    for path in paths {
        let before = settings.messagePreviewConfiguration
        settings[keyPath: path].toggle()
        check(before != settings.messagePreviewConfiguration, "preview must refresh for every setting")
    }

    func checkDescriptions() {
        let original = DGSimpleSettings.shared.stickerReplyOptions
        defer { DGSimpleSettings.shared.stickerReplyOptions = original }
        let cat = NSAttributedString(string: "стикер 😼")
        let sticker = FixtureMessage(media: [TelegramMediaFile(isSticker: true)])
        let regular = FixtureMessage(media: [])
        DGSimpleSettings.shared.hideStickerReplyEmoji = true
        check(replyDescription(isMediaValue: true, message: sticker, textStringValue: cat).string == "стикер", "cat emoji removed from the sticker description")
        check(replyDescription(isMediaValue: false, message: regular, textStringValue: cat) === cat, "ordinary message text and its attributes are preserved")
        check(replyDescription(isMediaValue: false, message: sticker, textStringValue: cat) === cat, "actual sticker caption text is preserved")
        DGSimpleSettings.shared.hideStickerReplyEmoji = false
        check(replyDescription(isMediaValue: true, message: sticker, textStringValue: cat) === cat, "emoji restored when toggle is off")
    }
    checkDescriptions()
    settings.hideStickerReplyColors = true
    settings.hideStickerReplyEmoji = true
    settings.hideStickerReplyBackground = false
    settings.hidePremiumReplyEmoji = true
    settings.commaAfterMention = true
    settings.mentionAvatars = true
    settings.showForwardDate = true
    defaults.synchronize()
} else {
    check(settings.stickerReplyOptions == 4, "individual sticker settings survive process restart")
    check(settings.hideStickerReplyColors && settings.hideStickerReplyEmoji && !settings.hideStickerReplyBackground, "hide switches restore correctly")
    check(settings.hidePremiumReplyEmoji, "premium decoration setting survives process restart")
    check(settings.commaAfterMention && settings.mentionAvatars && settings.showForwardDate, "preview controls survive process restart")
    settings.hidePremiumReplyEmoji = false
    check(settings.replyDecorationOptions(isSticker: false) == 7, "restoring premium decorations")
    defaults.removePersistentDomain(forName: suite)
}
print("message control behavior and persistence checks passed (\(mode))")
