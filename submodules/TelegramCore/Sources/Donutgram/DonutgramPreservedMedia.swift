import Foundation
import Postbox
import SwiftSignalKit

// A saved deleted message no longer exists on the server, so its files cannot be downloaded
// again (an expired file reference is refreshed through the message itself). Every path that
// clears the media cache therefore keeps the files these helpers collect.

private func donutgramAddResourceIds(image: TelegramMediaImage, to resourceIds: inout Set<MediaResourceId>) {
    for representation in image.representations {
        resourceIds.insert(representation.resource.id)
    }
    for representation in image.videoRepresentations {
        resourceIds.insert(representation.resource.id)
    }
    if let video = image.video {
        donutgramAddResourceIds(file: video, to: &resourceIds)
    }
}

private func donutgramAddResourceIds(file: TelegramMediaFile, to resourceIds: inout Set<MediaResourceId>) {
    resourceIds.insert(file.resource.id)
    for representation in file.previewRepresentations {
        resourceIds.insert(representation.resource.id)
    }
    for thumbnail in file.videoThumbnails {
        resourceIds.insert(thumbnail.resource.id)
    }
    if let videoCover = file.videoCover {
        donutgramAddResourceIds(image: videoCover, to: &resourceIds)
    }
    // The other qualities of a video: the one that was watched may be any of them.
    for alternative in file.alternativeRepresentations {
        donutgramAddResourceIds(file: alternative, to: &resourceIds)
    }
}

private func donutgramAddResourceIds(media: Media, to resourceIds: inout Set<MediaResourceId>) {
    if let image = media as? TelegramMediaImage {
        donutgramAddResourceIds(image: image, to: &resourceIds)
    } else if let file = media as? TelegramMediaFile {
        donutgramAddResourceIds(file: file, to: &resourceIds)
    } else if let webpage = media as? TelegramMediaWebpage {
        if case let .Loaded(content) = webpage.content {
            if let image = content.image {
                donutgramAddResourceIds(image: image, to: &resourceIds)
            }
            if let file = content.file {
                donutgramAddResourceIds(file: file, to: &resourceIds)
            }
        }
    } else if let game = media as? TelegramMediaGame {
        if let image = game.image {
            donutgramAddResourceIds(image: image, to: &resourceIds)
        }
        if let file = game.file {
            donutgramAddResourceIds(file: file, to: &resourceIds)
        }
    } else if let paidContent = media as? TelegramMediaPaidContent {
        for extendedMedia in paidContent.extendedMedia {
            if case let .full(fullMedia) = extendedMedia {
                donutgramAddResourceIds(media: fullMedia, to: &resourceIds)
            }
        }
    }
}

func donutgramAddMessageResourceIds(message: Message, to resourceIds: inout Set<MediaResourceId>) {
    for media in message.effectiveMedia {
        donutgramAddResourceIds(media: media, to: &resourceIds)
    }
}

/// `resourceIds` without the files of `messages`, the ones the user picked one by one.
func donutgramResourceIds(_ resourceIds: Set<MediaResourceId>, notPickedIn messages: [Message]) -> Set<MediaResourceId> {
    var pickedResourceIds = Set<MediaResourceId>()
    for message in messages {
        donutgramAddMessageResourceIds(message: message, to: &pickedResourceIds)
    }
    return resourceIds.subtracting(pickedResourceIds)
}

/// Folds `update` over the messages `messageIds`, a few hundred per transaction, so a large store
/// does not hold the Postbox queue for long.
private func donutgramReduceMessages<T>(postbox: Postbox, messageIds: [MessageId], into initialResult: T, _ update: @escaping (inout T, Message) -> Void) -> Signal<T, NoError> {
    let chunkSize = 256
    var signal: Signal<T, NoError> = .single(initialResult)
    var chunkStart = 0
    while chunkStart < messageIds.count {
        let chunk = messageIds[chunkStart ..< min(chunkStart + chunkSize, messageIds.count)]
        chunkStart += chunkSize
        signal = signal
        |> mapToSignal { result -> Signal<T, NoError> in
            return postbox.transaction { transaction -> T in
                var result = result
                for id in chunk {
                    if let message = transaction.getMessage(id) {
                        update(&result, message)
                    }
                }
                return result
            }
        }
    }
    return signal
}

/// The files of every saved deleted message of the account.
func donutgramPreservedMessageResourceIds(postbox: Postbox) -> Signal<Set<MediaResourceId>, NoError> {
    return postbox.transaction { transaction -> [MessageId] in
        return transaction.getMessageIdsWithLocalTag(.donutgramDeleted)
    }
    |> mapToSignal { messageIds -> Signal<Set<MediaResourceId>, NoError> in
        return donutgramReduceMessages(postbox: postbox, messageIds: messageIds, into: Set<MediaResourceId>(), { resourceIds, message in
            donutgramAddMessageResourceIds(message: message, to: &resourceIds)
        })
    }
}

public struct DonutgramPreservedMessagesUsage: Equatable {
    public struct Chat: Equatable {
        public var peerId: EnginePeer.Id
        /// Nil when the chat is no longer known to the account.
        public var peer: EnginePeer?
        public var messageCount: Int
        public var fileSize: Int64

        public init(peerId: EnginePeer.Id, peer: EnginePeer?, messageCount: Int, fileSize: Int64) {
            self.peerId = peerId
            self.peer = peer
            self.messageCount = messageCount
            self.fileSize = fileSize
        }
    }

    public var messageCount: Int
    /// A file that saved deleted messages of several chats show counts once here and in each chat.
    public var fileSize: Int64
    /// The chats that keep saved deleted messages, the largest first.
    public var chats: [Chat]

    public init(messageCount: Int, fileSize: Int64, chats: [Chat]) {
        self.messageCount = messageCount
        self.fileSize = fileSize
        self.chats = chats
    }
}

/// How many saved deleted messages the account keeps and how much their downloaded files take,
/// in all and per chat.
func _internal_donutgramPreservedMessagesUsage(postbox: Postbox) -> Signal<DonutgramPreservedMessagesUsage, NoError> {
    return postbox.transaction { transaction -> [MessageId] in
        return transaction.getMessageIdsWithLocalTag(.donutgramDeleted)
    }
    |> mapToSignal { messageIds -> Signal<DonutgramPreservedMessagesUsage, NoError> in
        let messageCounts = messageIds.reduce(into: [PeerId: Int]()) { counts, id in
            counts[id.peerId, default: 0] += 1
        }
        return donutgramReduceMessages(postbox: postbox, messageIds: messageIds, into: [PeerId: Set<MediaResourceId>](), { resourceIds, message in
            donutgramAddMessageResourceIds(message: message, to: &resourceIds[message.id.peerId, default: Set()])
        })
        |> mapToSignal { resourceIdsByPeer -> Signal<DonutgramPreservedMessagesUsage, NoError> in
            var allResourceIds = Set<MediaResourceId>()
            for (_, resourceIds) in resourceIdsByPeer {
                allResourceIds.formUnion(resourceIds)
            }
            let peersSignal = postbox.transaction { transaction -> [PeerId: EnginePeer] in
                var peers: [PeerId: EnginePeer] = [:]
                for peerId in messageCounts.keys {
                    if let peer = transaction.getPeer(peerId) {
                        peers[peerId] = EnginePeer(peer)
                    }
                }
                return peers
            }
            return combineLatest(postbox.mediaBox.collectResourceCacheUsage(Array(allResourceIds)), peersSignal)
            |> map { sizes, peers -> DonutgramPreservedMessagesUsage in
                var chats: [DonutgramPreservedMessagesUsage.Chat] = []
                for (peerId, messageCount) in messageCounts {
                    var fileSize: Int64 = 0
                    for resourceId in resourceIdsByPeer[peerId] ?? Set() {
                        fileSize += sizes[resourceId] ?? 0
                    }
                    chats.append(DonutgramPreservedMessagesUsage.Chat(peerId: peerId, peer: peers[peerId], messageCount: messageCount, fileSize: fileSize))
                }
                chats.sort { lhs, rhs in
                    if lhs.fileSize != rhs.fileSize {
                        return lhs.fileSize > rhs.fileSize
                    }
                    if lhs.messageCount != rhs.messageCount {
                        return lhs.messageCount > rhs.messageCount
                    }
                    return lhs.peerId < rhs.peerId
                }
                return DonutgramPreservedMessagesUsage(messageCount: messageIds.count, fileSize: sizes.values.reduce(0, +), chats: chats)
            }
        }
    }
}

/// Deletes the saved deleted messages of `peerId`, or of every chat when it is nil, with their edit
/// history and their downloaded files. Only the local copies are deleted: the messages are already
/// gone from the server. A file that a message still on the server shows as well downloads again
/// when it is opened; a file that a saved deleted message of another chat shows stays.
func _internal_donutgramDeletePreservedMessages(postbox: Postbox, peerId: EnginePeer.Id?) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> [MessageId] in
        let messageIds = transaction.getMessageIdsWithLocalTag(.donutgramDeleted)
        if let peerId {
            return messageIds.filter { $0.peerId == peerId }
        }
        return messageIds
    }
    |> mapToSignal { messageIds -> Signal<Never, NoError> in
        return donutgramReduceMessages(postbox: postbox, messageIds: messageIds, into: Set<MediaResourceId>(), { resourceIds, message in
            donutgramAddMessageResourceIds(message: message, to: &resourceIds)
        })
        |> mapToSignal { resourceIds -> Signal<Never, NoError> in
            // A few hundred per transaction, so a large store does not hold the Postbox queue.
            let chunkSize = 256
            var deleteMessages: Signal<Never, NoError> = .complete()
            var chunkStart = 0
            while chunkStart < messageIds.count {
                let chunk = Array(messageIds[chunkStart ..< min(chunkStart + chunkSize, messageIds.count)])
                chunkStart += chunkSize
                deleteMessages = deleteMessages
                |> then(postbox.transaction { transaction -> Void in
                    donutgramRemoveMessageRevisions(transaction: transaction, messageIds: chunk)
                    _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: chunk, deleteMedia: false)
                }
                |> ignoreValues)
            }
            // Read once the messages are gone: what is still saved keeps its files.
            let deleteFiles = donutgramPreservedMessageResourceIds(postbox: postbox)
            |> mapToSignal { keptResourceIds -> Signal<Never, NoError> in
                return postbox.mediaBox.removeCachedResourcesWithResult(Array(resourceIds.subtracting(keptResourceIds)))
                |> mapToSignal { removedIds -> Signal<Never, NoError> in
                    postbox.mediaBox.storageBox.remove(ids: removedIds.compactMap { $0.stringRepresentation.data(using: .utf8) })
                    return .complete()
                }
            }
            return deleteMessages
            |> then(deleteFiles)
        }
    }
}

public extension TelegramEngine.Messages {
    /// How many saved deleted messages the account keeps and how much their downloaded files take,
    /// in all and per chat.
    func donutgramPreservedMessagesUsage() -> Signal<DonutgramPreservedMessagesUsage, NoError> {
        return _internal_donutgramPreservedMessagesUsage(postbox: self.account.postbox)
    }

    /// Deletes the saved deleted messages of `peerId`, or of every chat when it is nil, with their
    /// edit history and their downloaded files.
    func donutgramDeletePreservedMessages(peerId: EnginePeer.Id?) -> Signal<Never, NoError> {
        return _internal_donutgramDeletePreservedMessages(postbox: self.account.postbox, peerId: peerId)
    }
}
