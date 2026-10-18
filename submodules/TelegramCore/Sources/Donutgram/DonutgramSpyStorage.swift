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
    guard let message = transaction.getMessage(messageId) else {
        return false
    }
    // A message that is already saved stays saved: the settings decide only about new deletions.
    if message.localTags.contains(.donutgramDeleted) {
        return true
    }
    guard donutgramAllowsSavingInPeer(transaction: transaction, peerId: messageId.peerId) else {
        return false
    }
    // Saved Messages are cleared by the account itself, on this or another device.
    if let accountState = transaction.getState() as? AuthorizedAccountState, accountState.peerId == messageId.peerId {
        return false
    }
    guard DGSimpleSettings.shared.saveDeletedMessages || message.localTags.contains(.donutgramSavedViewOnce) else {
        return false
    }
    // The update does not say who deleted an own message: the account on another device or, in a
    // private chat, the other side for both. Keeping them is a setting of its own.
    if !message.flags.contains(.Incoming) && !DGSimpleSettings.shared.saveOwnDeletedMessages {
        return false
    }

    transaction.updateMessage(messageId, update: { currentMessage in
        var localTags = currentMessage.localTags
        localTags.insert(.donutgramDeleted)
        return .update(donutgramMessageWithUpdatedLocalTags(currentMessage, localTags: localTags))
    })
    donutgramClearUnseenMarks(transaction: transaction, messageId: messageId)
    return true
}

/// The server can no longer read a saved deleted message, so it leaves the chat's mention, reaction
/// and poll vote badges as its deletion would have. The unread count leaves it out on its own
/// (`localTagsExcludedFromUnreadCount`).
private func donutgramClearUnseenMarks(transaction: Transaction, messageId: MessageId) {
    guard let message = transaction.getMessage(messageId) else {
        return
    }
    let unseenTags: MessageTags = [.unseenPersonalMessage, .unseenReaction, .unseenPollVote]
    var hasUnconsumedMention = false
    var hasPendingMention = false
    for attribute in message.attributes {
        if let attribute = attribute as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
            hasUnconsumedMention = true
            hasPendingMention = attribute.pending
        }
    }
    if message.tags.isDisjoint(with: unseenTags) && !hasUnconsumedMention {
        return
    }
    // A mention already read here but not yet on the server leaves the badge through its pending action.
    if hasPendingMention {
        transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: messageId, action: nil)
    }
    transaction.updateMessage(messageId, update: { currentMessage in
        var attributes = currentMessage.attributes
        for i in 0 ..< attributes.count {
            if let attribute = attributes[i] as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
                attributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: false)
            } else if let attribute = attributes[i] as? ReactionsMessageAttribute, attribute.hasUnseen {
                attributes[i] = attribute.withAllSeen()
            }
        }
        let media = currentMessage.media.map { item -> Media in
            if let poll = item as? TelegramMediaPoll, poll.results.hasUnseenVotes == true {
                return poll.withoutUnreadResults()
            }
            return item
        }
        var tags = currentMessage.tags
        tags.subtract(unseenTags)
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: media))
    })
}

/// Removes the stored messages of a chat in `minId ... maxId`, as the server does when it moves a
/// supergroup's first available message (its history was cleared). Saved deleted messages stay,
/// and the cleared messages are saved like any other deletion while saving is on.
func donutgramDeleteMessagesInRange(transaction: Transaction, peerId: PeerId, namespace: MessageId.Namespace, minId: MessageId.Id, maxId: MessageId.Id, forEachMedia: ((Media) -> Void)?) {
    var keptIds: [MessageId.Id] = []
    for id in transaction.getMessageIdsInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId) {
        if donutgramPreserveDeletedMessage(transaction: transaction, messageId: id) {
            keptIds.append(id.id)
        }
    }
    if keptIds.isEmpty {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: forEachMedia)
        return
    }

    var lowerBound = minId
    for keptId in keptIds.sorted() {
        if lowerBound < keptId {
            transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lowerBound, maxId: keptId - 1, forEachMedia: forEachMedia)
        }
        lowerBound = keptId + 1
    }
    if lowerBound <= maxId {
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: lowerBound, maxId: maxId, forEachMedia: forEachMedia)
    }
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

/// `updated`, a server copy about to replace the stored `previous`, with its edit history kept:
/// the text it replaces is stored as a revision and the edit-history marker stays.
func donutgramPreservingEditHistory(transaction: Transaction, previous: Message, updated: StoreMessage) -> StoreMessage {
    guard donutgramStorePreviousMessageRevision(transaction: transaction, previousMessage: previous, updatedText: updated.text), !updated.localTags.contains(.donutgramHasEditHistory) else {
        return updated
    }
    var localTags = updated.localTags
    localTags.insert(.donutgramHasEditHistory)
    return updated.withUpdatedLocalTags(localTags)
}

/// Stores the revisions that `messages`, server copies passed to `Transaction.addMessages`, are
/// about to replace. `addMessages` keeps the local tags of a stored message, so the marker goes
/// on the stored message first.
func donutgramStoreRevisionsOfReplacedMessages(transaction: Transaction, messages: [StoreMessage]) {
    guard DGSimpleSettings.shared.saveEditHistory else {
        return
    }
    for message in messages {
        // A copy without an edit date still has the text it was sent with.
        guard case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud, message.attributes.contains(where: { $0 is EditedMessageAttribute }), let previous = transaction.getMessage(id) else {
            continue
        }
        if donutgramStorePreviousMessageRevision(transaction: transaction, previousMessage: previous, updatedText: message.text) && !previous.localTags.contains(.donutgramHasEditHistory) {
            transaction.updateMessage(id, update: { currentMessage in
                var localTags = currentMessage.localTags
                localTags.insert(.donutgramHasEditHistory)
                return .update(donutgramMessageWithUpdatedLocalTags(currentMessage, localTags: localTags))
            })
        }
    }
}

func donutgramRemoveMessageRevisions(transaction: Transaction, messageIds: [MessageId]) {
    for id in messageIds {
        transaction.removeItemCacheEntry(id: donutgramRevisionCacheId(id))
    }
}

/// Drops the edit history of messages that are no longer stored (deleted, or removed with their
/// chat): nothing can show it, and the item cache never evicts it. A few hundred entries are
/// checked per transaction, so a long history does not hold the Postbox queue.
func donutgramRemoveOrphanedMessageRevisions(postbox: Postbox) -> Signal<Never, NoError> {
    let collectionId = Namespaces.CachedItemCollection.donutgramEditHistory
    return postbox.transaction { transaction -> [ValueBoxKey] in
        return transaction.getItemCacheEntryKeys(collectionId: collectionId)
    }
    |> mapToSignal { keys -> Signal<Never, NoError> in
        let chunkSize = 256
        var signal: Signal<Never, NoError> = .complete()
        var chunkStart = 0
        while chunkStart < keys.count {
            let chunk = keys[chunkStart ..< min(chunkStart + chunkSize, keys.count)]
            chunkStart += chunkSize
            signal = signal
            |> then(postbox.transaction { transaction -> Void in
                for key in chunk where key.length == 16 {
                    let messageId = MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8), id: key.getInt32(12))
                    if !transaction.messageExists(id: messageId) {
                        transaction.removeItemCacheEntry(id: ItemCacheEntryId(collectionId: collectionId, key: key))
                    }
                }
            }
            |> ignoreValues)
        }
        return signal
    }
}


/// Matches words and filename prefixes with the same case-insensitive semantics
/// as local chat search. Cloud messages are not in Postbox's secret-chat text index.
public func donutgramDeletedMessageMatchesQuery(text: String, query: String) -> Bool {
    return donutgramSearchWordsMatch(textWords: donutgramSearchWords(text), queryWords: donutgramSearchWords(query))
}

/// The words a text is searched by: case and diacritics folded (ё = е), split at everything that
/// is not a letter or a digit. Empty when the text has no letters or digits.
public func donutgramSearchWords(_ value: String) -> [String] {
    return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

/// Every query word is the start of some word of the text.
public func donutgramSearchWordsMatch(textWords: [String], queryWords: [String]) -> Bool {
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
        return donutgramDeletedMessageMatchesQuery(text: donutgramDeletedMessageSearchText(message), query: query)
    }.sorted { $0.index > $1.index }
}

/// The text a saved deleted message is found by: its own text and the searchable text of its media.
func donutgramDeletedMessageSearchText(_ message: Message) -> String {
    var text = message.text
    for media in message.media {
        if let indexableText = media.indexableText {
            text += " " + indexableText
        }
    }
    return text
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
