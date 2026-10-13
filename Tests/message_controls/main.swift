import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
final class TelegramMediaFile {
    let isSticker: Bool
    let isAnimatedSticker: Bool
    let isVideoSticker: Bool
    init(isSticker: Bool, animated: Bool = false, video: Bool = false) {
        self.isSticker = isSticker
        self.isAnimatedSticker = animated
        self.isVideoSticker = video
    }
}
struct ChatPreviewMessageItem {
    let sticker: TelegramMediaFile?
    // PRODUCTION_REUSE
}
struct FixtureBackground {
    var primaryColor = "blue"
    var secondaryColor: String?
    var backgroundColor: String?
    var isTransparent = false
}
func refreshBackground(previousParams: FixtureBackground?, params: FixtureBackground) -> Bool {
    return // PRODUCTION_BACKGROUND_CONDITION
}
// PRODUCTION_ARCHIVE_LAYOUT

struct FixtureColor: Equatable {
    let name: String
    static let clear = FixtureColor(name: "clear")
    func withAlphaComponent(_ alpha: CGFloat) -> FixtureColor { FixtureColor(name: name + " alpha") }
}
typealias UIColor = FixtureColor
struct FixtureMessageColors {
    let accentTextColor: UIColor
    let secondaryTextColor = FixtureColor(name: "secondary")
    let mediaPlaceholderColor = FixtureColor(name: "placeholder")
}
struct FixtureChatTheme {
    struct Message {
        let incoming = FixtureMessageColors(accentTextColor: FixtureColor(name: "incoming"))
        let outgoing = FixtureMessageColors(accentTextColor: FixtureColor(name: "outgoing"))
    }
    let message = Message()
}
struct FixtureTheme { let chat = FixtureChatTheme() }
struct FixtureThemeWrapper { let theme = FixtureTheme(); let wallpaper = 0 }
struct FixturePresentation { let theme = FixtureThemeWrapper() }
enum FixtureReplyType { case bubble(incoming: Bool); case standalone }
struct FixtureReplyArguments { let type: FixtureReplyType; let presentationData = FixturePresentation() }
struct FixtureServiceColors { let primaryText = FixtureColor(name: "service") }
func serviceMessageColorComponents(theme: FixtureTheme, wallpaper: Int) -> FixtureServiceColors { FixtureServiceColors() }
func serviceMessageColorComponents(chatTheme: FixtureChatTheme, wallpaper: Int) -> FixtureServiceColors { FixtureServiceColors() }
func replyColors(type: FixtureReplyType, isStickerReply: Bool, authorNameColor: UIColor?) -> (UIColor, UIColor) {
    let arguments = FixtureReplyArguments(type: type)
    let titleColor: UIColor
    let mainColor: UIColor
    let dustColor: UIColor
    let placeholderColor: UIColor
    let dashSecondaryColor: UIColor? = nil
    let dashTertiaryColor: UIColor? = nil
    var secondaryColor: UIColor?
    var tertiaryColor: UIColor?
    // PRODUCTION_REPLY_COLORS
    _ = (dustColor, placeholderColor, secondaryColor, tertiaryColor)
    return (titleColor, mainColor)
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

    let bubble = ChatPreviewMessageItem(sticker: nil)
    let staticSticker = ChatPreviewMessageItem(sticker: TelegramMediaFile(isSticker: true))
    let animatedSticker = ChatPreviewMessageItem(sticker: TelegramMediaFile(isSticker: true, animated: true))
    check(bubble.canReuseNode(with: bubble), "message preview updates reuse the same bubble")
    check(staticSticker.canReuseNode(with: staticSticker), "sticker decoration changes reuse the sticker node")
    check(!bubble.canReuseNode(with: staticSticker) && !staticSticker.canReuseNode(with: animatedSticker), "media kind changes require a compatible node")
    let originalBackground = FixtureBackground()
    var changedBackground = originalBackground
    check(!refreshBackground(previousParams: originalBackground, params: changedBackground), "unchanged backgrounds stay cached")
    changedBackground.backgroundColor = "clear"
    check(refreshBackground(previousParams: originalBackground, params: changedBackground), "hide background refreshes even with unchanged colors")
    check(refreshBackground(previousParams: changedBackground, params: originalBackground), "background restoration refreshes the fill")
    changedBackground = originalBackground
    changedBackground.isTransparent = true
    check(refreshBackground(previousParams: originalBackground, params: changedBackground), "transparent backgrounds refresh")
    let red = FixtureColor(name: "red")
    for type in [FixtureReplyType.bubble(incoming: true), .bubble(incoming: false), .standalone] {
        let visible = replyColors(type: type, isStickerReply: true, authorNameColor: red)
        let hidden = replyColors(type: type, isStickerReply: true, authorNameColor: nil)
        check(visible.0 == red && visible.1 == red, "sticker replies show author colors in every layout")
        check(hidden.0 != red && hidden.1 != red, "hiding sticker colors restores the theme colors")
    }
    check(replyColors(type: .bubble(incoming: false), isStickerReply: false, authorNameColor: red).0.name == "outgoing", "ordinary outgoing reply colors remain unchanged")
    check(donutgramArchiveRestoredOffset(-80, hideArchive: true, hasStories: false) == 0, "old archive offset cannot leave a blank row after restart")
    check(donutgramArchiveRestoredOffset(-80, hideArchive: true, hasStories: true) == -80, "visible stories keep their offset")
    check(donutgramArchiveRestoredOffset(100, hideArchive: true, hasStories: false) == 100, "scrolled-away chats keep their position")
    check(donutgramArchiveTopGapNeedsReset(hideArchive: true, isRoot: true, isTracking: false, isDecelerating: false, storiesInset: 0, offset: -80, removedArchive: true), "archive gap resets at the top")
    for dragging in [false, true] {
        for storiesInset in [CGFloat(0), CGFloat(80)] {
            let reset = donutgramArchiveTopGapNeedsReset(hideArchive: true, isRoot: true, isTracking: dragging, isDecelerating: false, storiesInset: storiesInset, offset: -80, removedArchive: true)
            check(reset == (!dragging && storiesInset == 0), "dragging and story expansion are respected")
        }
    }
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
