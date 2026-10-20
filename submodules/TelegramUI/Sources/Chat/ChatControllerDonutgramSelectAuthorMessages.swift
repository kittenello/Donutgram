import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import Display
import AccountContext
import OverlayStatusController
import PresentationDataUtils
import UndoUI
import DGSimpleSettings

extension ChatControllerImpl {
    /// The action of «Выбрать все сообщения: …» for the pressed message's author, or nil where it is not offered:
    /// where one author writes everything (Saved Messages, a channel's own posts), or, in a chat whose history is
    /// not the server's (scheduled messages, quick replies), when it would select no more than «Select» does.
    func donutgramSelectAuthorMessagesAction(pressedMessages: [EngineRawMessage]) -> (() -> Void)? {
        guard let topMessage = pressedMessages.first, let authorId = topMessage.author?.id, topMessage.id.peerId != self.context.account.peerId else {
            return nil
        }
        if let channel = self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel, case .broadcast = channel.info {
            return nil
        }

        let searchesServer: Bool
        switch self.chatLocation {
        case .peer, .replyThread:
            searchesServer = self.subject == nil
        case .customChatContents:
            searchesServer = false
        }
        if !searchesServer {
            let pressedIds = Set(pressedMessages.map(\.id))
            if !self.donutgramLoadedAuthorMessageIds(authorId: authorId).contains(where: { !pressedIds.contains($0) }) {
                return nil
            }
        }

        // The server addresses an author without an access hash through one of their messages, so it must be a message
        // the server still has: not a local one and not a saved deleted one.
        let sourceMessageId: EngineMessage.Id? = topMessage.id.namespace == Namespaces.Message.Cloud && !topMessage.localTags.contains(.donutgramDeleted) ? topMessage.id : nil
        return { [weak self] in
            self?.donutgramSelectAuthorMessages(authorId: authorId, sourceMessageId: sourceMessageId, searchesServer: searchesServer)
        }
    }

    /// The author's selectable messages in the loaded history window, without a reply thread's head.
    private func donutgramLoadedAuthorMessageIds(authorId: EnginePeer.Id) -> [EngineMessage.Id] {
        let historyNode = self.chatDisplayNode.historyNode
        let excludedIds = self.donutgramUnselectableThreadHeadIds()
        return donutgramSelectableMessageIds(author: authorId, forEachLoadedMessage: { f in
            historyNode.forEachMessageInCurrentHistoryView(f)
        }).filter { !excludedIds.contains($0) }
    }

    /// A reply thread's head (an album head with all its items) is drawn without a selection checkbox, so it must not be
    /// selected unseen and then deleted or forwarded with the replies.
    private func donutgramUnselectableThreadHeadIds() -> Set<EngineMessage.Id> {
        var result = Set<EngineMessage.Id>()
        if case let .replyThread(replyThreadMessage) = self.chatLocation {
            result.insert(replyThreadMessage.effectiveTopId)
            if let headGroup = self.chatDisplayNode.historyNode.messageGroupInCurrentHistoryView(replyThreadMessage.effectiveTopId) {
                result.formUnion(headGroup.map(\.id))
            }
        }
        return result
    }

    private func donutgramSelectAuthorMessages(authorId: EnginePeer.Id, sourceMessageId: EngineMessage.Id?, searchesServer: Bool) {
        guard searchesServer, let peerId = self.chatLocation.peerId else {
            self.interfaceInteraction?.beginMessageSelection(self.donutgramLoadedAuthorMessageIds(authorId: authorId), { _ in })
            return
        }

        let presentationData = self.presentationData
        let disposable = MetaDisposable()
        var progressController: ViewController?
        var isFinished = false
        // A spinner only when the server takes a moment, with cancel for a long history.
        Queue.mainQueue().after(0.15, { [weak self] in
            if isFinished {
                return
            }
            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
                isFinished = true
                disposable.dispose()
                progressController?.dismiss()
                progressController = nil
            }))
            progressController = controller
            self?.present(controller, in: .window(.root))
        })

        disposable.set((self.context.engine.messages.donutgramAuthorMessages(peerId: peerId, threadId: self.chatLocation.threadId, authorId: authorId, sourceMessageId: sourceMessageId)
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard case let .result(messages, isComplete) = result else {
                return
            }
            isFinished = true
            progressController?.dismiss()
            progressController = nil
            guard let self else {
                return
            }

            // The window adds what the server does not have yet, such as messages still being sent.
            let excludedIds = self.donutgramUnselectableThreadHeadIds()
            var seen = Set<EngineMessage.Id>()
            var ids: [EngineMessage.Id] = []
            let foundIds = donutgramSelectableMessageIds(author: authorId, forEachLoadedMessage: { f in
                for message in messages {
                    if !f(message) {
                        break
                    }
                }
            })
            for id in foundIds + self.donutgramLoadedAuthorMessageIds(authorId: authorId) {
                if !excludedIds.contains(id), seen.insert(id).inserted {
                    ids.append(id)
                }
            }
            if ids.isEmpty {
                return
            }
            self.interfaceInteraction?.beginMessageSelection(ids, { _ in })

            if !isComplete {
                let languageCode = presentationData.strings.primaryComponent.languageCode
                self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: dgLocalized("Не все сообщения удалось загрузить, выбраны только найденные.", languageCode: languageCode), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            }
        }))
    }
}
