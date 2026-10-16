import Foundation
import UIKit
import Display
import ContextUI
import DGSimpleSettings

extension ChatControllerImpl {
    /// «В начало чата» for the menu of the chat's avatar: loads the start of the history and scrolls to the
    /// very first message. Nil when it is switched off in Donutgram's settings.
    func donutgramJumpToStartContextMenuItem() -> ContextMenuItem? {
        guard DGSimpleSettings.shared.jumpToStartInChatMenu else {
            return nil
        }
        let text = dgLocalized("В начало чата", languageCode: self.presentationData.strings.primaryComponent.languageCode)
        return .action(ContextMenuActionItem(text: text, icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "arrow.up.to.line", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)), color: theme.actionSheet.primaryTextColor)
        }, action: { [weak self] _, f in
            f(.dismissWithoutContent)
            self?.scrollToStartOfHistory()
        }))
    }
}
