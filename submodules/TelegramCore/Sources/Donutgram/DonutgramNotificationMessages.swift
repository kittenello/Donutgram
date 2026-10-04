import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit
import DGSimpleSettings

/// Called only after successfully decrypting a push with a cloud message id.
/// The push's alert may be truncated, localized or a reaction, so fetch the
/// full API message instead of constructing a chat message from alert text.
public func donutgramCaptureNotificationMessage(
    accountPeerId: PeerId,
    postbox: Postbox,
    network: Network,
    messageId: MessageId
) -> Signal<Never, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace != Namespaces.Peer.SecretChat,
          DGSimpleSettings.shared.saveDeletedMessages else {
        return .complete()
    }

    return postbox.transaction { transaction -> (Bool, Api.InputChannel?) in
        guard DGSimpleSettings.shared.saveDeletedMessages,
              donutgramAllowsSavingInPeer(transaction: transaction, peerId: messageId.peerId),
              transaction.getMessage(messageId) == nil else {
            return (false, nil)
        }
        let channel = transaction.getPeer(messageId.peerId).flatMap(apiInputChannel)
        return (true, channel)
    }
    |> mapToSignal { shouldFetch, channel -> Signal<Never, NoError> in
        guard shouldFetch else {
            return .complete()
        }
        let inputIds: [Api.InputMessage] = [.inputMessageID(.init(id: messageId.id))]
        let request: Signal<Api.messages.Messages, MTRpcError>
        switch messageId.peerId.namespace {
        case Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup:
            request = network.request(Api.functions.messages.getMessages(id: inputIds), automaticFloodWait: false)
        case Namespaces.Peer.CloudChannel:
            guard let channel else {
                return .complete()
            }
            request = network.request(Api.functions.channels.getMessages(channel: channel, id: inputIds), automaticFloodWait: false)
        default:
            return .complete()
        }

        return request
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
            return .single(nil)
        }
        // Leave the extension time to deliver the original notification on failure.
        |> timeout(3.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
        |> mapToSignal { result -> Signal<Never, NoError> in
            guard let result else {
                return .complete()
            }
            let messages: [Api.Message]
            let chats: [Api.Chat]
            let users: [Api.User]
            switch result {
            case let .messages(data):
                (messages, chats, users) = (data.messages, data.chats, data.users)
            case let .messagesSlice(data):
                (messages, chats, users) = (data.messages, data.chats, data.users)
            case let .channelMessages(data):
                (messages, chats, users) = (data.messages, data.chats, data.users)
            case .messagesNotModified:
                return .complete()
            }
            return postbox.transaction { transaction -> Void in
                let peers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: peers)
                // Recheck settings and bot identity after the request. A different
                // process may have already stored a newer edit or deletion marker.
                guard DGSimpleSettings.shared.saveDeletedMessages,
                      donutgramAllowsSavingInPeer(transaction: transaction, peerId: messageId.peerId),
                      transaction.getMessage(messageId) == nil else {
                    return
                }
                let peerIsForum = transaction.getPeer(messageId.peerId)?.isForumOrMonoForum ?? false
                for apiMessage in messages {
                    guard case .message = apiMessage,
                          let message = StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: peerIsForum),
                          donutgramIsNotificationMessage(message, expectedId: messageId) else {
                        continue
                    }
                    // Postbox is shared with the app and encrypted with its account key.
                    // It commits before the following difference/deletion is processed.
                    _ = transaction.addMessages([message], location: .Random)
                }
            } |> ignoreValues
        }
    }
}

func donutgramIsNotificationMessage(_ message: StoreMessage, expectedId: MessageId) -> Bool {
    guard case let .Id(id) = message.id else {
        return false
    }
    return id == expectedId && message.flags.contains(.Incoming)
}

/// This is exclusively for server deletion pushes, not the user's delete action.
public func donutgramDeleteMessagesFromNotification(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
    let idsToDelete = ids.filter { !donutgramPreserveDeletedMessage(transaction: transaction, messageId: $0) }
    _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: idsToDelete, deleteMedia: true)
}
