import Foundation
import Postbox

// A reply to a message that only this client still keeps (a deleted message saved by
// "Сохранять удалённые") is a pseudo-reply: PendingMessageManager drops the reply and sends
// the reference as a blockquote with the author and the quote in front of the body. Postbox
// keeps the local form instead: the body alone, the reply to the deleted message and
// `.donutgramPseudoReply`. Every server copy carries the quote again, so each place that
// writes a server copy over a stored message goes through `donutgramPreservingLocalState`.
// A scheduled pseudo-reply (ghost mode sends everything as scheduled) is published as a new
// message, which gets the local form of the scheduled one.

private func donutgramStoreMessage(_ message: Message) -> StoreMessage {
    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: message.attributes, media: message.media)
}

/// The reply to the deleted message that a stored pseudo-reply shows.
private func donutgramLocalReply(_ message: Message) -> ReplyMessageAttribute? {
    guard message.localTags.contains(.donutgramPseudoReply) else {
        return nil
    }
    return message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute
}

private func donutgramEntities(_ message: StoreMessage) -> [MessageTextEntity] {
    return (message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
}

/// The blockquote at the start of a text: where a pseudo-reply carries its quote.
private func donutgramLeadingQuote(_ entities: [MessageTextEntity]) -> MessageTextEntity? {
    return entities.first(where: { entity in
        if case .BlockQuote = entity.type, entity.range.lowerBound == 0 {
            return true
        } else {
            return false
        }
    })
}

/// Returns `updated`, a copy of a pseudo-reply whose local form is `localText` under
/// `localReply`, in that local form: the body without the quote, the reply to the deleted
/// message and the local tags (`pseudoReplyTags`, see donutgramPseudoReplyLocalTags). The
/// body is taken from `updated`, so an edit made elsewhere shows up. `prefix`, the quote the
/// pseudo-reply went out with, stays for later edits (donutgramPreservingPseudoReply).
private func donutgramLocalPseudoReplyCopy(localReply: ReplyMessageAttribute, localText: String, pseudoReplyTags: LocalMessageTags, prefix: DonutgramPseudoReplyPrefixMessageAttribute?, updated: StoreMessage) -> StoreMessage {
    let localTags = updated.localTags.union(.donutgramPseudoReply).union(pseudoReplyTags)
    // Already the local form: a local update, or the copy of a message that went out as a
    // normal reply because the deleted message was gone by the time it was sent.
    if updated.attributes.contains(where: { ($0 as? ReplyMessageAttribute)?.messageId == localReply.messageId }) {
        return updated.withUpdatedLocalTags(localTags)
    }

    var text = updated.text
    var entities = donutgramEntities(updated)
    var tags = updated.tags
    var globalTags = updated.globalTags
    var isStripped = false
    // A copy equal to the local body carries no quote: later items of an album, later parts
    // of a split text, a quote that did not fit. A copy without the blockquote (removed by an
    // edit elsewhere) is all body.
    if updated.text != localText, let quote = donutgramLeadingQuote(entities) {
        let serverText = updated.text as NSString
        // The body follows the quote and a line break. The server can leave trailing spaces
        // of the quote outside the entity; a sent body starts with none.
        let separators: [unichar] = [0x20, 0x09, 0x0a, 0x0d]
        var bodyStart = min(quote.range.upperBound, serverText.length)
        while bodyStart < serverText.length, separators.contains(serverText.character(at: bodyStart)) {
            bodyStart += 1
        }
        // A text message edited elsewhere down to the quote alone keeps its server text
        // rather than turning into an empty bubble.
        if bodyStart < serverText.length || updated.media.contains(where: { !($0 is TelegramMediaWebpage) }) {
            text = serverText.substring(from: bodyStart)
            entities = messageTextEntitiesInRange(entities: entities, range: NSRange(location: bodyStart, length: serverText.length - bodyStart), onlyQuoteable: false)
            isStripped = true
        }
    }

    var attributes = updated.attributes.filter { !donutgramIsPseudoReplyLocalAttribute($0) }
    attributes.append(localReply)
    if !entities.isEmpty {
        attributes.append(TextEntitiesMessageAttribute(entities: entities))
    }
    if let prefix {
        attributes.append(prefix)
    }
    if isStripped {
        // A link that was only in the quote no longer puts the message into the shared links.
        (tags, globalTags) = tagsForStoreMessage(incoming: updated.flags.contains(.Incoming), attributes: attributes, media: updated.media, textEntities: entities, isPinned: updated.tags.contains(.pinned))
    }
    return StoreMessage(id: updated.id, customStableId: updated.customStableId, globallyUniqueId: updated.globallyUniqueId, groupingKey: updated.groupingKey, threadId: updated.threadId, timestamp: updated.timestamp, flags: updated.flags, tags: tags, globalTags: globalTags, localTags: localTags, forwardInfo: updated.forwardInfo, authorId: updated.authorId, text: text, attributes: attributes, media: updated.media)
}

/// Returns `updated`, a server copy about to replace the stored `previous`, in the local form
/// of a pseudo-reply. Every write of a server copy goes through it, `.EditMessage` included,
/// so they all agree on the body.
func donutgramPseudoReplyLocalForm(previous: Message, updated: StoreMessage) -> StoreMessage {
    guard let localReply = donutgramLocalReply(previous) else {
        return updated
    }
    // A pseudo-reply sent by this build stores the quote that went out: cut exactly that. If
    // the server text no longer starts with it, the quote was removed or changed elsewhere.
    if donutgramStoredPseudoReplyPrefix(previous) != nil {
        return donutgramPreservingPseudoReply(previous: previous, updated: updated)
    }
    return donutgramLocalPseudoReplyCopy(localReply: localReply, localText: previous.text, pseudoReplyTags: donutgramPseudoReplyLocalTags(previous), prefix: nil, updated: updated)
}

/// The local form of a scheduled pseudo-reply whose published copy is not stored yet.
private struct DonutgramScheduledPseudoReply: Codable {
    let reply: Data
    let text: String
    let mediaIds: [MediaId]
    // The quote it went out with and whether it is a later part of a split text; nil in an
    // entry stored before they were kept.
    let prefix: String?
    let isContinuation: Bool?
}

private func donutgramPublishedPseudoReplyKey(_ id: MessageId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 16)
    key.setInt64(0, value: id.peerId.toInt64())
    key.setInt32(8, value: id.namespace)
    key.setInt32(12, value: id.id)
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.donutgramPublishedPseudoReplies, key: key)
}

/// `published`, a new copy of a message that was sent as scheduled, in the local form of its
/// scheduled pseudo-reply, or nil when it is none.
private func donutgramPublishedPseudoReplyCopy(transaction: Transaction, id: MessageId, published: StoreMessage) -> StoreMessage? {
    let mediaIds = published.media.compactMap { $0.id }
    let key = donutgramPublishedPseudoReplyKey(id)
    if let entry = transaction.retrieveItemCacheEntry(id: key) {
        transaction.removeItemCacheEntry(id: key)
        if let scheduled = entry.get(DonutgramScheduledPseudoReply.self), scheduled.mediaIds == mediaIds, let localReply = PostboxDecoder(buffer: MemoryBuffer(data: scheduled.reply)).decodeRootObject() as? ReplyMessageAttribute {
            let pseudoReplyTags: LocalMessageTags = scheduled.isContinuation == true ? .donutgramPseudoReplyContinuation : []
            let localCopy = donutgramLocalPseudoReplyCopy(localReply: localReply, localText: scheduled.text, pseudoReplyTags: pseudoReplyTags, prefix: scheduled.prefix.map { DonutgramPseudoReplyPrefixMessageAttribute(text: $0) }, updated: published)
            if localCopy.text == scheduled.text {
                return localCopy
            }
        }
    }
    // The delete of the scheduled copy, which pairs it with this one, can be missed while
    // the app is suspended. Then the scheduled copy is still stored: find it by content and
    // by date, as a scheduled message goes out at its schedule date.
    guard donutgramLeadingQuote(donutgramEntities(published)) != nil else {
        return nil
    }
    let maxDistance: Int32 = 60
    var best: (distance: Int32, copy: StoreMessage)?
    var isDone = false
    transaction.scanTopMessages(peerId: id.peerId, namespace: Namespaces.Message.ScheduledCloud, limit: 100, { scheduled in
        // Postbox keeps paging after `false`, so the scan stops through `isDone`.
        if isDone {
            return false
        }
        // Newest schedule date first.
        let distance = scheduled.timestamp - published.timestamp
        if distance < -maxDistance {
            isDone = true
            return false
        }
        guard distance <= maxDistance, let localReply = donutgramLocalReply(scheduled), scheduled.media.compactMap({ $0.id }) == mediaIds else {
            return true
        }
        let localCopy = donutgramLocalPseudoReplyCopy(localReply: localReply, localText: scheduled.text, pseudoReplyTags: donutgramPseudoReplyLocalTags(scheduled), prefix: donutgramStoredPseudoReplyPrefix(scheduled), updated: published)
        if localCopy.text == scheduled.text && abs(distance) < (best?.distance ?? Int32.max) {
            best = (distance: abs(distance), copy: localCopy)
        }
        return true
    })
    return best?.copy
}

/// Returns `updated`, a server copy about to replace the stored `previous`, with the state
/// that only this client keeps: saved view-once media, the local form of a pseudo-reply and
/// the edit history (the text it replaces is stored as a revision).
func donutgramPreservingLocalState(transaction: Transaction, previous: Message, updated: StoreMessage) -> StoreMessage {
    let updated = donutgramPseudoReplyLocalForm(previous: previous, updated: donutgramPreservingSavedViewOnceMedia(previous: previous, updated: updated))
    return donutgramPreservingEditHistory(transaction: transaction, previous: previous, updated: updated)
}

/// `donutgramPreservingLocalState(transaction:previous:updated:)` for server messages passed to
/// `Transaction.addMessages`, which replaces the text, attributes and media of a message
/// that is already stored. A published scheduled pseudo-reply gets its local form as well.
func donutgramPreservingLocalState(transaction: Transaction, messages: [StoreMessage]) -> [StoreMessage] {
    let result = donutgramPreservingSavedViewOnceMedia(transaction: transaction, messages: messages).map { message -> StoreMessage in
        // Pseudo-replies are outgoing.
        guard !message.flags.contains(.Incoming), case let .Id(id) = message.id else {
            return message
        }
        if let previous = transaction.getMessage(id) {
            return donutgramPseudoReplyLocalForm(previous: previous, updated: message)
        } else if message.flags.contains(.WasScheduled), let localCopy = donutgramPublishedPseudoReplyCopy(transaction: transaction, id: id, published: message) {
            return localCopy
        } else {
            return message
        }
    }
    donutgramStoreRevisionsOfReplacedMessages(transaction: transaction, messages: result)
    return result
}

/// `updateDeleteScheduledMessages` pairs published messages with their scheduled copies,
/// which are deleted right after. Gives the published copy of a pseudo-reply the local form
/// of the scheduled one, or keeps that form until the published copy is stored (it comes
/// later after a pts gap).
func donutgramMovePseudoRepliesToSentMessages(transaction: Transaction, scheduledIds: [MessageId], sentIds: [MessageId]) {
    for (scheduledId, sentId) in zip(scheduledIds, sentIds) {
        guard let scheduled = transaction.getMessage(scheduledId), let localReply = donutgramLocalReply(scheduled) else {
            continue
        }
        let mediaIds = scheduled.media.compactMap { $0.id }
        let pseudoReplyTags = donutgramPseudoReplyLocalTags(scheduled)
        let prefix = donutgramStoredPseudoReplyPrefix(scheduled)
        if transaction.messageExists(id: sentId) {
            transaction.updateMessage(sentId, update: { current in
                guard current.media.compactMap({ $0.id }) == mediaIds, donutgramLocalReply(current)?.messageId != localReply.messageId else {
                    return .skip
                }
                let localCopy = donutgramLocalPseudoReplyCopy(localReply: localReply, localText: scheduled.text, pseudoReplyTags: pseudoReplyTags, prefix: prefix, updated: donutgramStoreMessage(current))
                // Both copies have the same body; anything else is not the published copy.
                return localCopy.text == scheduled.text ? .update(localCopy) : .skip
            })
        } else {
            let encoder = PostboxEncoder()
            encoder.encodeRootObject(localReply)
            if let entry = CodableEntry(DonutgramScheduledPseudoReply(reply: encoder.makeData(), text: scheduled.text, mediaIds: mediaIds, prefix: prefix?.text, isContinuation: pseudoReplyTags.contains(.donutgramPseudoReplyContinuation))) {
                transaction.putItemCacheEntry(id: donutgramPublishedPseudoReplyKey(sentId), entry: entry)
            }
        }
    }
}
