import Foundation
import UIKit
import Display
import TelegramCore
import PresentationDataUtils
import DGSimpleSettings

extension ChatControllerImpl {
    /// «Подтверждать реакции без вступления»: adding `reaction` in a channel or group the account has not joined is
    /// asked about first. Removing a reaction never is, and Stars reactions have their own confirmation.
    func donutgramReactionNeedsConfirmation(_ reaction: MessageReaction.Reaction) -> Bool {
        guard DGSimpleSettings.shared.confirmReactionsInUnjoinedChats else {
            return false
        }
        if case .stars = reaction {
            return false
        }
        guard let channel = self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel else {
            return false
        }
        return channel.participationStatus != .member
    }

    /// Asks whether to react in a chat that has not been joined, and runs `apply` on «Да».
    func donutgramPresentReactionConfirmation(apply: @escaping () -> Void) {
        let presentationData = self.presentationData
        let languageCode = presentationData.strings.primaryComponent.languageCode
        self.present(textAlertController(context: self.context, title: nil, text: dgLocalized("Вы точно хотите поставить реакцию в чате, в который еще не вступили?", languageCode: languageCode), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_No, action: {}),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Yes, action: apply)
        ]), in: .window(.root))
    }
}
