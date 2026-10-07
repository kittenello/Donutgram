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

    func isEqual(to other: ItemListItemTag) -> Bool {
        return (other as? DGSettingItemTag)?.key == self.key
    }
}

// The page part of a setting link, tg://settings/donutgram/<page>/<key>. Links get copied and shared,
// so a raw value never changes, whatever happens to the case name or the page title.
// Each page has its own case: its factory passes it to dgController,
// and dgSettingsControllerForLink maps it back to that factory.
enum DGSettingsPage: String {
    case root
    case general
    case ghost
    case ghostOptions = "ghost-options"
    case silent
    case appearance
    case iconAndIsland = "icon-and-island"
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
    case downloads
    case transcription
    case reactions
    case visualId = "visual-id"
    case visualRating = "visual-rating"
    case visualUsernames = "visual-usernames"
    case visualPhone = "visual-phone"
    case shadowBan = "shadow-ban"
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

    private func target(at point: CGPoint, in controller: ItemListController) -> (key: String, view: UIView)? {
        var found: (key: String, view: UIView)?
        controller.forEachItemNode { node in
            guard found == nil,
                  let tag = (node as? ItemListItemNode)?.tag as? DGSettingItemTag,
                  node.view.bounds.contains(node.view.convert(point, from: controller.view)) else {
                return
            }
            found = (tag.key, node.view)
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
              let target = self.target(at: gesture.location(in: controller.view), in: controller),
              let url = URL(string: "tg://settings/donutgram/\(self.page.rawValue)/\(target.key)") else {
            return
        }
        // Telegram's sheet, not a UIAlertController: that one follows the iOS appearance instead of the app theme.
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: dgLocalized("Копировать ссылку", languageCode: presentationData.strings.primaryComponent.languageCode), action: { [weak actionSheet, weak controller] in
                actionSheet?.dismissAnimated()
                UIPasteboard.general.string = url.absoluteString
                controller?.present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
            }),
            ActionSheetButtonItem(title: dgLocalized("Поделиться ссылкой", languageCode: presentationData.strings.primaryComponent.languageCode), action: { [weak actionSheet, weak controller] in
                actionSheet?.dismissAnimated()
                let share = UIActivityViewController(activityItems: [url.absoluteString], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = target.view
                share.popoverPresentationController?.sourceRect = target.view.bounds
                controller?.present(share, animated: true)
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        // The sheet ignores the keyboard inset: with a text field focused it would open under the keyboard.
        controller.view.endEditing(true)
        controller.present(actionSheet, in: .window(.root))
    }
}
