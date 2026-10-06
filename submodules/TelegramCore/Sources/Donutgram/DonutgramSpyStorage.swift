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


/// Matches words and filename prefixes with the same case-insensitive semantics
/// as local chat search. Cloud messages are not in Postbox's secret-chat text index.
public func donutgramDeletedMessageMatchesQuery(text: String, query: String) -> Bool {
    func words(_ value: String) -> [String] {
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
    let queryWords = words(query)
    let textWords = words(text)
    return queryWords.allSatisfy { queryWord in
        textWords.contains { $0.hasPrefix(queryWord) }
    }
}

func donutgramDeletedMessages(
    transaction: Transaction,
    peerId: PeerId,
    query: String = "",
    fromId: PeerId? = nil,
    tags: MessageTags? = nil,
    reactions: [MessageReaction.Reaction]? = nil,
    threadId: Int64? = nil,
    minDate: Int32? = nil,
    maxDate: Int32? = nil
) -> [Message] {
    return transaction.getMessagesWithLocalTag(.donutgramDeleted, peerId: peerId).filter { message in
        guard message.id.namespace == Namespaces.Message.Cloud else { return false }
        if let fromId, message.author?.id != fromId { return false }
        if let tags, !message.tags.contains(tags) { return false }
        if let threadId, message.threadId != threadId { return false }
        if let minDate, minDate != 0, message.timestamp < minDate { return false }
        if let maxDate, maxDate != 0, message.timestamp > maxDate { return false }
        if let reactions, !reactions.isEmpty {
            let messageReactions = message.attributes.compactMap { $0 as? ReactionsMessageAttribute }.flatMap { $0.reactions }
            if !reactions.allSatisfy({ reaction in messageReactions.contains { $0.value == reaction } }) { return false }
        }
        var text = message.text
        for media in message.media {
            if let indexableText = media.indexableText {
                text += " " + indexableText
            }
        }
        return donutgramDeletedMessageMatchesQuery(text: text, query: query)
    }.sorted { $0.index > $1.index }
}

/// Includes local results only inside the loaded remote window. Older deletions
/// become visible as server pages arrive, keeping search navigation contiguous.
public func donutgramSearchResultIncludingDeletedMessages(_ result: SearchMessagesResult, deletedMessages: [Message]) -> SearchMessagesResult {
    var uniqueLocal: [MessageId: Message] = [:]
    for message in deletedMessages {
        uniqueLocal[message.id] = message
    }
    let remoteIds = Set(result.messages.map { $0.id })
    let extraCount = uniqueLocal.keys.filter { !remoteIds.contains($0) }.count
    let oldestRemoteIndex = result.messages.last?.index
    let visibleLocal = uniqueLocal.values.filter { message in
        result.completed || oldestRemoteIndex.map { message.index >= $0 } == true
    }
    let localIds = Set(visibleLocal.map { $0.id })
    var messages = result.messages.filter { !localIds.contains($0.id) }
    messages.append(contentsOf: visibleLocal)
    messages.sort { $0.index > $1.index }
    return SearchMessagesResult(messages: messages, readStates: result.readStates, threadInfo: result.threadInfo, totalCount: result.totalCount + Int32(clamping: extraCount), completed: result.completed)
}
