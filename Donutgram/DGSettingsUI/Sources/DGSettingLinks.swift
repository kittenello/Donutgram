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

private enum DGSettingDescription {
    private static let downloads = "Когда вы отправляете ссылку на TikTok или YouTube Shorts, Donutgram скачивает ролик и отправляет его собеседнику вместо ссылки."

    static let byKey: [String: String] = [
        "removePings": "Когда вас упомянут, отдельной отметки и уведомления об упоминании не будет.",
        "anonymousStickerSending": "Отправляет стикер без привязки к набору. Собеседник не сможет открыть набор по этому стикеру.",
        "hideVerification": "Скрывает значки верификации Hold, Major и других сервисов.",
        "downloadTikTok": downloads,
        "downloadShorts": downloads,
        "hideViaBot": "Скрывает подпись «через бота» над сообщениями.",
        "blurMessages": "Блюр сообщений, работает только с кастомными обоями",
        "hideAIFeatures": "Скрывает кнопки функций ИИ в редакторах сообщений и подписей.",
        "removeLinkPreviews": "Отправляет ссылки без карточек предпросмотра.",
        "neutralComposeButton": "Использует обычный цвет для кнопки нового сообщения в списке чатов.",
        "gifUnlock": "Отправляет GIF как видео без звука. Обход не сработает, если в чате запрещена отправка видео.",
        "stickerUnlock": "Отправляет стикеры как видео без звука. Обход не сработает, если в чате запрещена отправка видео.",
        "bypassContentRestrictions": "Открывает чаты и каналы, недоступные из-за ограничений именно на iPhone.",
        "disappearedGifts": "Показывает скрытые и удалённые обычные подарки; NFT не запоминаются. Для этого нужно хотя бы один раз открыть профиль человека, пока подарок ещё виден.",
        "telegramStatistics": "Аналитика приложения, время чтения постов в каналах, прослушанная музыка, служебные логи и данные о качестве звонков, как в обычном Telegram. Сетевая телеметрия не отправляется никогда.",
        "hideBlocked": "Сообщения тех, кого вы заблокировали, скрыты в группах и комментариях, как в теневом бане. Боты не скрываются: остановленный бот тоже числится заблокированным.",
        "pollResultsBeforeVoting": "Если в опросе можно отменить голос, вы увидите, сколько человек выбрали каждый вариант, ещё до своего голоса.",
        "hideServiceMessages": "Скрывает служебные сообщения о вступлении в группу, выходе из неё и других событиях.",
        "keepBannedChats": "Если вас забанили в чате, он останется в списке и вы сможете читать его историю. Новые сообщения появляться не будут."
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
    case plugins
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

    func install() {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(DGSettingsLongPressHandler.handle(_:)))
        gesture.delegate = self
        self.controller?.view.addGestureRecognizer(gesture)
    }

    private func target(at point: CGPoint, in controller: ItemListController) -> (tag: DGSettingItemTag, node: ListViewItemNode)? {
        var found: (tag: DGSettingItemTag, node: ListViewItemNode)?
        controller.forEachItemNode { node in
            guard found == nil,
                  let tag = (node as? ItemListItemNode)?.tag as? DGSettingItemTag,
                  CGRect(origin: .zero, size: node.contentSize).contains(node.view.convert(point, from: controller.view)) else {
                return
            }
            found = (tag, node)
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
            sourceNode: target.node,
            presentationData: presentationData,
            description: description ?? target.tag.title,
            copy: { [weak controller] in
                UIPasteboard.general.string = url.absoluteString
                controller?.present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
            },
            share: { [weak controller, weak sourceView = target.node.view] in
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
    private weak var sourceNode: ListViewItemNode?
    private weak var sourceView: UIView?
    private let presentationData: PresentationData
    private let detail: String?
    private let copy: () -> Void
    private let share: () -> Void

    init(sourceNode: ListViewItemNode, presentationData: PresentationData, description: String?, copy: @escaping () -> Void, share: @escaping () -> Void) {
        let sourceView = sourceNode.view
        self.sourceNode = sourceNode
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
            let bounds = CGRect(origin: .zero, size: sourceNode.contentSize)
            let inset = min(62.0, bounds.width * 0.25)
            let anchorX = sourceView.effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - inset : bounds.minX + inset
            popover.sourceRect = CGRect(x: anchorX, y: bounds.minY, width: 1.0, height: bounds.height).insetBy(dx: 0.0, dy: -4.0)
            popover.permittedArrowDirections = [.up, .down]
            let theme = presentationData.theme
            popover.backgroundColor = theme.actionSheet.opaqueItemBackgroundColor.mixedWith(theme.contextMenu.primaryColor, alpha: 0.12)
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
            scrollView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
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
        if let popover = self.popoverPresentationController, let sourceView = self.sourceView, let window = sourceView.window {
            let anchor = sourceView.convert(popover.sourceRect, to: window)
            let bottom = window.safeAreaLayoutGuide.layoutFrame.maxY - popover.popoverLayoutMargins.bottom
            if bottom - anchor.maxY >= self.preferredContentSize.height + 24.0 {
                popover.permittedArrowDirections = .up
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.sourceNode?.setHighlighted(true, at: .zero, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.clearHighlight()
    }

    func clearHighlight() {
        self.sourceNode?.setHighlighted(false, at: .zero, animated: false)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }

    override func accessibilityPerformEscape() -> Bool {
        self.dismiss(animated: true)
        return true
    }
}
