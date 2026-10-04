import Foundation
import Postbox
import SwiftSignalKit
import DGSimpleSettings

public struct DonutgramMessageRevision: Codable, Equatable {
    public let text: String
    public let timestamp: Int32

    public init(text: String, timestamp: Int32) {
        self.text = text
        self.timestamp = timestamp
    }
}

private struct DonutgramMessageRevisionList: Codable {
    var revisions: [DonutgramMessageRevision]
}

private func donutgramMessageWithUpdatedLocalTags(_ message: Message, localTags: LocalMessageTags) -> StoreMessage {
    return StoreMessage(
        id: message.id,
        customStableId: nil,
        globallyUniqueId: message.globallyUniqueId,
        groupingKey: message.groupingKey,
        threadId: message.threadId,
        timestamp: message.timestamp,
        flags: StoreMessageFlags(message.flags),
        tags: message.tags,
        globalTags: message.globalTags,
        localTags: localTags,
        forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init),
        authorId: message.author?.id,
        text: message.text,
        attributes: message.attributes,
        media: message.media
    )
}

private func donutgramRevisionCacheId(_ messageId: MessageId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 16)
    key.setInt64(0, value: messageId.peerId.toInt64())
    key.setInt32(8, value: messageId.namespace)
    key.setInt32(12, value: messageId.id)
    return ItemCacheEntryId(
        collectionId: Namespaces.CachedItemCollection.donutgramEditHistory,
        key: key
    )
}

func donutgramAllowsSavingInPeer(transaction: Transaction, peerId: PeerId) -> Bool {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return false
    }

    if DGSimpleSettings.shared.saveInBotChats {
        return true
    }

    if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
        return false
    }

    return true
}

private func donutgramRevisionTimestamp(_ message: Message) -> Int32 {
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute, attribute.date != 0 {
            return attribute.date
        }
    }
    return message.timestamp
}

/// Marks a cloud message as locally deleted instead of removing it from Postbox.
///
/// Keeping the original Message object means its text, attributes and media
/// references stay available after reopening the chat and after an app restart.
/// The marker is local-only and is never sent to Telegram.
func donutgramPreserveDeletedMessage(transaction: Transaction, messageId: MessageId) -> Bool {
    guard messageId.namespace == Namespaces.Message.Cloud else {
        return false
    }
    guard donutgramAllowsSavingInPeer(transaction: transaction, peerId: messageId.peerId) else {
        return false
    }
    guard let message = transaction.getMessage(messageId) else {
        return false
    }
    guard DGSimpleSettings.shared.saveDeletedMessages || message.localTags.contains(.donutgramSavedViewOnce) else {
        return false
    }

    if message.localTags.contains(.donutgramDeleted) {
        return true
    }

    transaction.updateMessage(messageId, update: { currentMessage in
        var localTags = currentMessage.localTags
        localTags.insert(.donutgramDeleted)
        return .update(donutgramMessageWithUpdatedLocalTags(currentMessage, localTags: localTags))
    })
    return true
}

/// Stores the version that is about to be replaced by an incoming edit.
/// Returns true when the message should carry the local edit-history marker.
func donutgramStorePreviousMessageRevision(
    transaction: Transaction,
    previousMessage: Message,
    updatedText: String
) -> Bool {
    guard DGSimpleSettings.shared.saveEditHistory else {
        return previousMessage.localTags.contains(.donutgramHasEditHistory)
    }
    guard previousMessage.id.namespace == Namespaces.Message.Cloud else {
        return previousMessage.localTags.contains(.donutgramHasEditHistory)
    }
    guard previousMessage.text != updatedText else {
        return previousMessage.localTags.contains(.donutgramHasEditHistory)
    }
    guard donutgramAllowsSavingInPeer(transaction: transaction, peerId: previousMessage.id.peerId) else {
        return previousMessage.localTags.contains(.donutgramHasEditHistory)
    }

    let cacheId = donutgramRevisionCacheId(previousMessage.id)
    var list = transaction.retrieveItemCacheEntry(id: cacheId)?.get(DonutgramMessageRevisionList.self)
        ?? DonutgramMessageRevisionList(revisions: [])

    let revision = DonutgramMessageRevision(
        text: previousMessage.text,
        timestamp: donutgramRevisionTimestamp(previousMessage)
    )

    if list.revisions.last != revision {
        list.revisions.append(revision)

        // A pathological message can be edited many times. Keep the newest
        // revisions while bounding the local cache.
        if list.revisions.count > 100 {
            list.revisions.removeFirst(list.revisions.count - 100)
        }

        guard let entry = CodableEntry(list) else {
            return previousMessage.localTags.contains(.donutgramHasEditHistory)
        }
        transaction.putItemCacheEntry(id: cacheId, entry: entry)
    }

    return true
}

public func donutgramMessageRevisions(
    postbox: Postbox,
    messageId: MessageId
) -> Signal<[DonutgramMessageRevision], NoError> {
    return postbox.transaction { transaction -> [DonutgramMessageRevision] in
        let cacheId = donutgramRevisionCacheId(messageId)
        return transaction.retrieveItemCacheEntry(id: cacheId)?
            .get(DonutgramMessageRevisionList.self)?
            .revisions ?? []
    }
}

