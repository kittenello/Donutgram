import Foundation
import DGSimpleSettings
import UIKit
import AsyncDisplayKit
import ItemListUI
import Display
import AccountContext
import TelegramPresentationData
import UndoUI

struct DGSettingItemTag: ItemListItemTag {
    let key: String
    let title: String?

    init(key: String, title: String? = nil) {
        self.key = key
        self.title = title
    }

    func isEqual(to other: ItemListItemTag) -> Bool {
        return (other as? DGSettingItemTag)?.key == self.key
    }
}

enum DGSettingDescription {
    static let mentions = "Когда вас упомянут, отдельной отметки и уведомления об упоминании не будет."
    static let invisibleAdmins = "Если у администратора невидимый префикс, вместо него покажется «админ»."
    static let anonymousStickers = "Отправляет стикер без привязки к набору. Собеседник не сможет открыть набор по этому стикеру."
    static let verification = "Скрывает значки верификации Hold, Major и других сервисов."
    static let downloads = "Когда вы отправляете ссылку на TikTok или YouTube Shorts, Donutgram скачивает ролик и отправляет его собеседнику вместо ссылки."
    static let gifUnlock = "Отправляет GIF как видео без звука. Обход не сработает, если в чате запрещена отправка видео."
    static let stickerUnlock = "Отправляет стикеры как видео без звука. Обход не сработает, если в чате запрещена отправка видео."
    static let bypassContentRestrictions = "Открывает чаты и каналы, недоступные из-за ограничений именно на iPhone."
    static let disappearedGifts = "Показывает скрытые, проданные и удалённые подарки. Для этого нужно хотя бы один раз открыть профиль человека, пока подарок ещё виден."
    static let telegramStatistics = "Аналитика приложения, время чтения постов в каналах, прослушанная музыка, служебные логи и данные о качестве звонков, как в обычном Telegram. Сетевая телеметрия не отправляется никогда."

    static let byKey: [String: String] = [
        "removePings": mentions,
        "showInvisibleAdmins": invisibleAdmins,
        "anonymousStickerSending": anonymousStickers,
        "hideVerification": verification,
        "downloadTikTok": downloads,
        "downloadShorts": downloads,
        "hideViaBot": "Скрывает подпись «через бота» над сообщениями.",
        "hideAIFeatures": "Скрывает кнопки функций ИИ в редакторах сообщений и подписей.",
        "removeLinkPreviews": "Отправляет ссылки без карточек предпросмотра.",
        "neutralComposeButton": "Использует обычный цвет для кнопки нового сообщения в списке чатов.",
        "gifUnlock": gifUnlock,
        "stickerUnlock": stickerUnlock,
        "bypassContentRestrictions": bypassContentRestrictions,
        "disappearedGifts": disappearedGifts,
        "telegramStatistics": telegramStatistics
    ]
}

// The page part of a setting link, tg://settings/donutgram/<page>/<key>. Links get copied and shared,
// so a raw value never changes, whatever happens to the case name or the page title.
// Each page has its own case: its factory passes it to dgController,
// and dgSettingsControllerForLink maps it back to that factory.
enum DGSettingsPage: String {
    case root
    // The sections of the root, in its order.
    case ghost
    case saving
    case bypass
    case shadowBan = "shadow-ban"
    case mainScreen = "main-screen"
    case messages
    case stickers
    case profiles
    case iconAndEffects = "icon-and-effects"
    case media
    case downloads
    case security
    case adsAndGifts = "ads-and-gifts"
    case localProfile = "local-profile"
    case about
    // The screens opened from a section.
    case iconAndIsland = "icon-and-island"
    case visualId = "visual-id"
    case visualRating = "visual-rating"
    case visualUsernames = "visual-usernames"
    case visualPhone = "visual-phone"
    case visualLabel = "visual-label"
    case savedDeleted = "saved-deleted"
    // Pages that are gone: their rows moved into the sections, and the one-choice pages became menus in a row.
    // Kept so that links copied before still open, at the row that took their place.
    case general
    case ghostOptions = "ghost-options"
    case silent
    case appearance
    case dialogId = "dialog-id"
    case chats
    case channelBottomButton = "channel-bottom-button"
    case glow
    case stickerReplies = "sticker-replies"
    case chatListAppearance = "chat-list-appearance"
    case chatListTitle = "chat-list-title"
    case doubleTapSeek = "double-tap-seek"
    case camera
    case autoplayMedia = "autoplay-media"
    case autoPause = "auto-pause"
    case musicPlaybackExceptions = "music-playback-exceptions"
    case transcription
    case reactions
    case support
}

// displayHighlight() for the DG items that draw their block with a UIView, as ItemListUI draws it:
// the search highlight color under the content, inside the block's corners, for 1.2 s.
func dgDisplayHighlight(in blockView: UIView, theme: PresentationTheme) {
    let highlightView = UIView(frame: blockView.bounds)
    highlightView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    highlightView.backgroundColor = theme.list.itemSearchHighlightColor
    highlightView.isUserInteractionEnabled = false
    blockView.insertSubview(highlightView, at: 0)
    UIView.animate(withDuration: 0.3, delay: 1.2, options: [], animations: {
        highlightView.alpha = 0.0
    }, completion: { _ in
        highlightView.removeFromSuperview()
    })
}

final class DGSettingsLongPressHandler: NSObject, UIGestureRecognizerDelegate {
    let context: AccountContext
    weak var controller: ItemListController?
    let page: DGSettingsPage

    init(context: AccountContext, controller: ItemListController, page: DGSettingsPage) {
        self.context = context
        self.controller = controller
        self.page = page
    }

    private func target(at point: CGPoint, in controller: ItemListController) -> (tag: DGSettingItemTag, view: UIView)? {
        var found: (tag: DGSettingItemTag, view: UIView)?
        controller.forEachItemNode { node in
            guard found == nil,
                  let tag = (node as? ItemListItemNode)?.tag as? DGSettingItemTag,
                  node.view.bounds.contains(node.view.convert(point, from: controller.view)) else {
                return
            }
            found = (tag, node.view)
        }
        return found
    }

    // Only a hold on a list row opens the menu. Touches outside the list (the navigation bar over a row scrolled
    // under it, a toast) and on a row's own control (switch, slider, text field, clear button) keep their behavior.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var currentView = touch.view
        while let view = currentView {
            if view is UIControl || view.asyncdisplaykit_node is ASControlNode {
                return false
            }
            if view is ListViewBackingView {
                return true
            }
            currentView = view.superview
        }
        return false
    }

    // Beginning cancels the touch in the list, so it must not begin where there is no link to show.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let controller = self.controller else {
            return false
        }
        return self.target(at: gestureRecognizer.location(in: controller.view), in: controller) != nil
    }

    @objc func handle(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let controller = self.controller,
              let target = self.target(at: gesture.location(in: controller.view), in: controller) else {
            return
        }
        let link: String
        if self.page == .about, let aboutLink = dgAboutLinkUrl(key: target.tag.key) {
            // A row that shows a link, the channel or the source code, gives that link, as a Telegram profile does:
            // a link to the row would open only in Donutgram.
            link = aboutLink
        } else if self.page == .root, let section = dgRootSectionPage(target.tag.key) {
            // A section row of the root links to the section itself, tg://settings/donutgram/<page>: opening the root
            // only to flash the row is a step short of what the link is copied for.
            link = "tg://settings/donutgram/\(section.rawValue)"
        } else {
            link = "tg://settings/donutgram/\(self.page.rawValue)/\(target.tag.key)"
        }
        guard let url = URL(string: link) else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let description = DGSettingDescription.byKey[target.tag.key].map { dgLocalized($0, languageCode: languageCode) }
        let menu = DGSettingMenuController(
            sourceView: target.view,
            presentationData: presentationData,
            description: description ?? target.tag.title,
            copy: { [weak controller] in
                UIPasteboard.general.string = url.absoluteString
                controller?.present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
            },
            share: { [weak controller, weak sourceView = target.view] in
                guard let controller else {
                    return
                }
                let share = UIActivityViewController(activityItems: [url.absoluteString], applicationActivities: nil)
                let anchor: UIView = sourceView.flatMap { $0.window == nil ? nil : $0 } ?? controller.view
                share.popoverPresentationController?.sourceView = anchor
                share.popoverPresentationController?.sourceRect = anchor.bounds
                controller.present(share, animated: true)
            }
        )
        controller.view.endEditing(true)
        menu.loadViewIfNeeded()
        controller.present(menu, animated: true)
    }
}

private final class DGSettingMenuController: UIViewController, UIPopoverPresentationControllerDelegate {
    private weak var sourceView: UIView?
    private let presentationData: PresentationData
    private let detail: String?
    private let copy: () -> Void
    private let share: () -> Void
    private let highlight = UIView()

    init(sourceView: UIView, presentationData: PresentationData, description: String?, copy: @escaping () -> Void, share: @escaping () -> Void) {
        self.sourceView = sourceView
        self.presentationData = presentationData
        self.detail = description
        self.copy = copy
        self.share = share
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .popover
        self.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
        if let popover = self.popoverPresentationController {
            popover.delegate = self
            popover.sourceView = sourceView
            let bounds = sourceView.bounds
            let inset = min(62.0, bounds.width * 0.25)
            let anchorX = sourceView.effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - inset : bounds.minX + inset
            popover.sourceRect = CGRect(x: anchorX, y: bounds.minY, width: 1.0, height: bounds.height)
            popover.permittedArrowDirections = [.up, .down]
            popover.backgroundColor = presentationData.theme.actionSheet.opaqueItemBackgroundColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = self.presentationData.theme
        let languageCode = self.presentationData.strings.primaryComponent.languageCode
        let scrollView = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        self.view.accessibilityViewIsModal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        if let detail = self.detail, !detail.isEmpty {
            let label = UILabel()
            label.text = detail
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = theme.contextMenu.secondaryColor
            label.numberOfLines = 0
            let detailView = UIStackView(arrangedSubviews: [label])
            detailView.isLayoutMarginsRelativeArrangement = true
            detailView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12.0, leading: 16.0, bottom: 12.0, trailing: 16.0)
            stack.addArrangedSubview(detailView)
        }

        let actions = [
            (dgLocalized("Копировать ссылку", languageCode: languageCode), "doc.on.doc", self.copy),
            (dgLocalized("Поделиться ссылкой", languageCode: languageCode), "square.and.arrow.up", self.share)
        ]
        for (title, icon, action) in actions {
            if !stack.arrangedSubviews.isEmpty {
                let separator = UIView()
                separator.backgroundColor = theme.contextMenu.itemSeparatorColor
                stack.addArrangedSubview(separator)
                separator.heightAnchor.constraint(equalToConstant: UIScreenPixel).isActive = true
            }
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.image = UIImage(systemName: icon)
            configuration.imagePadding = 11.0
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 9.0, leading: 16.0, bottom: 9.0, trailing: 16.0)
            configuration.baseForegroundColor = theme.contextMenu.primaryColor
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true, completion: action)
            })
            button.contentHorizontalAlignment = .leading
            stack.addArrangedSubview(button)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0).isActive = true
        }

        let width = min(310.0, max(220.0, (self.sourceView?.bounds.width ?? 350.0) - 40.0))
        let fittedSize = stack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        self.preferredContentSize = CGSize(width: width, height: ceil(fittedSize.height))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sourceView = self.sourceView {
            self.highlight.frame = sourceView.bounds.insetBy(dx: 16.0, dy: 1.0)
            self.highlight.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.highlight.isUserInteractionEnabled = false
            self.highlight.layer.cornerRadius = 12.0
            self.highlight.backgroundColor = self.presentationData.theme.contextMenu.primaryColor.withAlphaComponent(0.10)
            sourceView.addSubview(self.highlight)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.highlight.removeFromSuperview()
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }

    override func accessibilityPerformEscape() -> Bool {
        self.dismiss(animated: true)
        return true
    }
}
