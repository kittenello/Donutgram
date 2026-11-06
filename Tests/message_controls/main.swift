import Foundation

struct FixtureRankedMember: Equatable {
    enum Role: Equatable { case creator, admin, member }
    let role: Role
    let rank: String?
    // PRODUCTION_ADMIN_DISPLAY_RANK
}

final class FixtureRankTheme {}
enum FixtureRankEntry: Equatable {
    case addMember(FixtureRankTheme, String)
    case member(FixtureRankTheme, Int, FixtureRankedMember, String?)
    // PRODUCTION_ADMIN_RANK_EQUALITY
}

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
    check(!settings.showInvisibleAdmins, "hidden admin badges are opt-in")
    let invisibleTitles = [
        "", " ", "\t\n", "\u{00a0}", "\u{200b}", "\u{200c}\u{200d}", "\u{2060}",
        "\u{202a}\u{202c}", "\u{feff}", "\u{034f}", "\u{115f}", "\u{1160}",
        "\u{3164}", "\u{ffa0}", "\u{2800}", "\u{1d159}", "\u{fffc}", " \u{200b}\u{2800}\u{3164}\n"
    ]
    let visibleTitles = ["админ", "модератор", "🛡️", "👩‍💻", " \u{200b}Главный\u{200d} ", "а\u{0301}"]
    for title in invisibleTitles + visibleTitles {
        check(settings.visibleAdminTitle(title) == title, "disabled leaves every custom title unchanged")
    }
    settings.showInvisibleAdmins = true
    check(settings.visibleAdminTitle(nil) == nil, "no rank keeps the standard role label")
    for title in invisibleTitles {
        check(settings.visibleAdminTitle(title) == nil, "invisible-only titles fall back to the localized role")
    }
    for title in visibleTitles {
        check(settings.visibleAdminTitle(title) == title, "readable and emoji titles stay byte-for-byte unchanged")
    }
    do {
        let original = DGSimpleSettings.shared.showInvisibleAdmins
        defer { DGSimpleSettings.shared.showInvisibleAdmins = original }
        let theme = FixtureRankTheme()
        let admin = FixtureRankedMember(role: .admin, rank: "\u{200b}")
        DGSimpleSettings.shared.showInvisibleAdmins = false
        let before = FixtureRankEntry.member(theme, 0, admin, admin.donutgramDisplayRank)
        DGSimpleSettings.shared.showInvisibleAdmins = true
        let after = FixtureRankEntry.member(theme, 0, admin, admin.donutgramDisplayRank)
        check(before != after, "an unchanged member row updates immediately when the visible title changes")
        for role in [FixtureRankedMember.Role.admin, .creator] {
            let member = FixtureRankedMember(role: role, rank: "\u{200b}")
            check(member.donutgramDisplayRank == nil, "known admins and owners use the normal role badge")
            check(member.rank == "\u{200b}", "displaying a badge never rewrites the server title")
        }
        let regular = FixtureRankedMember(role: .member, rank: "\u{200b}")
        check(regular.donutgramDisplayRank == regular.rank, "an ordinary member is never marked as admin")
        DGSimpleSettings.shared.showInvisibleAdmins = false
        check(before == FixtureRankEntry.member(theme, 0, admin, admin.donutgramDisplayRank), "switching off restores the original member row")
        check(FixtureRankedMember(role: .admin, rank: "\u{200b}").donutgramDisplayRank == "\u{200b}", "switching off restores the original badge")
    }
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
    let incomingVisible = replyColors(type: .bubble(incoming: true), isStickerReply: true, authorNameColor: red)
    let incomingHidden = replyColors(type: .bubble(incoming: true), isStickerReply: true, authorNameColor: nil)
    check(incomingVisible.0 == red && incomingVisible.1 == red, "incoming sticker replies show author colors")
    check(incomingHidden.0 != red && incomingHidden.1 != red, "hiding sticker colors restores the theme colors")
    for isStickerReply in [false, true] {
        for authorNameColor in [Optional(red), nil] {
            let outgoing = replyColors(type: .bubble(incoming: false), isStickerReply: isStickerReply, authorNameColor: authorNameColor)
            check(outgoing.0.name == "outgoing" && outgoing.1.name == "outgoing", "outgoing replies keep the stock accent color")
            let standalone = replyColors(type: .standalone, isStickerReply: isStickerReply, authorNameColor: authorNameColor)
            check(standalone.0.name == "service" && standalone.1.name == "service", "replies above stickers and round videos keep the stock service color")
        }
    }
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
    check(settings.showInvisibleAdmins, "admin badge preference survives a process restart")
    check(settings.visibleAdminTitle("\u{200b}\u{2800}") == nil, "the persisted preference restores the visible badge")
    check(settings.stickerReplyOptions == 4, "individual sticker settings survive process restart")
    check(settings.hideStickerReplyColors && settings.hideStickerReplyEmoji && !settings.hideStickerReplyBackground, "hide switches restore correctly")
    check(settings.hidePremiumReplyEmoji, "premium decoration setting survives process restart")
    check(settings.commaAfterMention && settings.mentionAvatars && settings.showForwardDate, "preview controls survive process restart")
    settings.hidePremiumReplyEmoji = false
    check(settings.replyDecorationOptions(isSticker: false) == 7, "restoring premium decorations")
    defaults.removePersistentDomain(forName: suite)
}
print("message control behavior and persistence checks passed (\(mode))")
