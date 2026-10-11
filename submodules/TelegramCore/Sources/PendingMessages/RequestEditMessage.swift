import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit


public enum RequestEditMessageMedia : Equatable {
    case keep
    case update(AnyMediaReference)
}

public enum RequestEditMessageResult {
    case progress(Float)
    case done(Bool)
}

private enum RequestEditMessageInternalError {
    case error(RequestEditMessageError)
    case invalidReference
}

public enum RequestEditMessageError {
    case generic
    case restricted
    case textTooLong
    case invalidGrouping
}

func _internal_requestEditMessage(account: Account, messageId: MessageId, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?, inlineStickers: [MediaId: Media], webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool, scheduleInfoAttribute: OutgoingScheduleInfoMessageAttribute?, invertMediaAttribute: InvertMediaMessageAttribute?) -> Signal<RequestEditMessageResult, RequestEditMessageError> {
    return requestEditMessage(accountPeerId: account.peerId, postbox: account.postbox, network: account.network, stateManager: account.stateManager, transformOutgoingMessageMedia: account.transformOutgoingMessageMedia, messageMediaPreuploadManager: account.messageMediaPreuploadManager, mediaReferenceRevalidationContext: account.mediaReferenceRevalidationContext, messageId: messageId, text: text, media: media, entities: entities, richText: richText, inlineStickers: inlineStickers, webpagePreviewAttribute: webpagePreviewAttribute, disableUrlPreview: disableUrlPreview, scheduleInfoAttribute: scheduleInfoAttribute, invertMediaAttribute: invertMediaAttribute)
}

func requestEditMessage(accountPeerId: PeerId, postbox: Postbox, network: Network, stateManager: AccountStateManager, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, mediaReferenceRevalidationContext: MediaReferenceRevalidationContext, messageId: MessageId, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?, inlineStickers: [MediaId: Media], webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool, scheduleInfoAttribute: OutgoingScheduleInfoMessageAttribute?, invertMediaAttribute: InvertMediaMessageAttribute?) -> Signal<RequestEditMessageResult, RequestEditMessageError> {
    return requestEditMessageInternal(accountPeerId: accountPeerId, postbox: postbox, network: network, stateManager: stateManager, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, mediaReferenceRevalidationContext: mediaReferenceRevalidationContext, messageId: messageId, text: text, media: media, entities: entities, richText: richText, inlineStickers: inlineStickers, webpagePreviewAttribute: webpagePreviewAttribute, invertMediaAttribute: invertMediaAttribute, disableUrlPreview: disableUrlPreview, scheduleInfoAttribute: scheduleInfoAttribute, forceReupload: false)
    |> `catch` { error -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> in
        if case .invalidReference = error {
            return requestEditMessageInternal(accountPeerId: accountPeerId, postbox: postbox, network: network, stateManager: stateManager, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, mediaReferenceRevalidationContext: mediaReferenceRevalidationContext, messageId: messageId, text: text, media: media, entities: entities, richText: richText, inlineStickers: inlineStickers, webpagePreviewAttribute: webpagePreviewAttribute, invertMediaAttribute: invertMediaAttribute, disableUrlPreview: disableUrlPreview, scheduleInfoAttribute: scheduleInfoAttribute, forceReupload: true)
        } else {
            return .fail(error)
        }
    }
    |> mapError { error -> RequestEditMessageError in
        switch error {
            case let .error(error):
                return error
            default:
                return .generic
        }
    }
}

// Donutgram: a pseudo-reply is stored as its body alone, while its server copy
// starts with a quote of the deleted message (donutgramPseudoReplyContent). The
// editor holds only that body, so the edit has to quote again, or the quote is
// gone for everyone else. A copy that a server echo already overwrote shows the
// quote in its text and has no local reply left, so it gets no second quote.
private func donutgramPseudoReplyEditContent(transaction: Transaction, accountPeerId: PeerId, message: Message, text: String, entities: TextEntitiesMessageAttribute?, associatedPeers: SimpleDictionary<PeerId, Peer>) -> (String, [Api.MessageEntity])? {
    guard message.localTags.contains(.donutgramPseudoReply) else {
        return nil
    }
    var attributes = message.attributes.filter { !($0 is TextEntitiesMessageAttribute) }
    if let entities {
        attributes.append(entities)
    }
    var peers = message.peers
    for (peerId, peer) in associatedPeers {
        peers[peerId] = peer
    }
    // Any media but a link preview makes the text a caption, with its own length limit
    // (paid media included, as at sending).
    let isCaption = message.media.contains(where: { !($0 is TelegramMediaWebpage) })
    guard let content = donutgramPseudoReplyContent(transaction: transaction, message: message.withUpdatedText(text).withUpdatedAttributes(attributes).withUpdatedPeers(peers), accountPeerId: accountPeerId, isCaption: isCaption) else {
        return nil
    }
    // An album quotes the deleted message once, in the caption of its first item.
    if message.groupingKey != nil, let first = transaction.getMessageGroup(message.id)?.first, first.id != message.id {
        return (text, entities.map { apiTextAttributeEntities($0, associatedPeers: peers) } ?? [])
    }
    return content
}

// Donutgram: after such an edit the server copy has the quote in its text instead
// of the reply to the deleted message. Keep the pseudo-reply as it was stored after
// sending: that reply, the body as typed, and the local tags a server copy never has.
// This holds only for the edited message, and only while its stored copy still has
// that reply: a server echo may have replaced it with the server form meanwhile.
private func donutgramKeepingPseudoReply(previous: Message, updated: StoreMessage, localBody: (messageId: MessageId, text: String, entities: TextEntitiesMessageAttribute?)?) -> StoreMessage {
    guard let localBody, previous.id == localBody.messageId, previous.localTags.contains(.donutgramPseudoReply), previous.attributes.contains(where: { $0 is ReplyMessageAttribute }) else {
        return updated
    }
    var attributes = updated.attributes.filter { !($0 is ReplyMessageAttribute || $0 is TextEntitiesMessageAttribute) }
    attributes.append(contentsOf: previous.attributes.filter { $0 is ReplyMessageAttribute })
    if let entities = localBody.entities {
        attributes.append(entities)
    }
    return updated.withUpdatedText(localBody.text).withUpdatedAttributes(attributes).withUpdatedLocalTags(updated.localTags.union(previous.localTags))
}

private func requestEditMessageInternal(accountPeerId: PeerId, postbox: Postbox, network: Network, stateManager: AccountStateManager, transformOutgoingMessageMedia: TransformOutgoingMessageMedia?, messageMediaPreuploadManager: MessageMediaPreuploadManager, mediaReferenceRevalidationContext: MediaReferenceRevalidationContext, messageId: MessageId, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?, inlineStickers: [MediaId: Media], webpagePreviewAttribute: WebpagePreviewMessageAttribute?, invertMediaAttribute: InvertMediaMessageAttribute?, disableUrlPreview: Bool, scheduleInfoAttribute: OutgoingScheduleInfoMessageAttribute?, forceReupload: Bool) -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> {
    let uploadedMedia: Signal<PendingMessageUploadedContentResult?, NoError>
    switch media {
    case .keep:
        uploadedMedia = .single(.progress(PendingMessageUploadedContentProgress(progress: 0.0)))
        |> then(.single(nil))
    case let .update(media):
        let generateUploadSignal: (Bool) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>? = { forceReupload in
            let augmentedMedia = augmentMediaWithReference(media)
            var attributes: [MessageAttribute] = []
            if let webpagePreviewAttribute = webpagePreviewAttribute {
                attributes.append(webpagePreviewAttribute)
            }
            if let invertMediaAttribute {
                attributes.append(invertMediaAttribute)
            }
            return mediaContentToUpload(accountPeerId: accountPeerId, network: network, postbox: postbox, auxiliaryMethods: stateManager.auxiliaryMethods, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messageMediaPreuploadManager: messageMediaPreuploadManager, revalidationContext: mediaReferenceRevalidationContext, forceReupload: forceReupload, isGrouped: false, passFetchProgress: false, forceNoBigParts: false, peerId: messageId.peerId, media: augmentedMedia, text: "", autoremoveMessageAttribute: nil, autoclearMessageAttribute: nil, messageId: nil, attributes: attributes, mediaReference: nil, explicitPartialReference: nil)
        }
        if let todo = media.media as? TelegramMediaTodo {
            var flags: Int32 = 0
            if todo.flags.contains(.othersCanAppend) {
                flags |= 1 << 0
            }
            if todo.flags.contains(.othersCanComplete) {
                flags |= 1 << 1
            }
            let inputTodo = Api.InputMedia.inputMediaTodo(.init(todo: .todoList(.init(flags: flags, title: .textWithEntities(.init(text: todo.text, entities: apiEntitiesFromMessageTextEntities(todo.textEntities, associatedPeers: SimpleDictionary()))), list: todo.items.map { $0.apiItem }))))
            uploadedMedia = .single(.content(PendingMessageUploadedContentAndReuploadInfo(content: .media(inputTodo, text), reuploadInfo: nil, cacheReferenceKey: nil)))
        }
        else if let uploadSignal = generateUploadSignal(forceReupload) {
            uploadedMedia = .single(.progress(PendingMessageUploadedContentProgress(progress: 0.027)))
            |> then(uploadSignal)
            |> map { result -> PendingMessageUploadedContentResult? in
                switch result {
                case let .progress(value):
                    return .progress(PendingMessageUploadedContentProgress(progress: max(value.progress, 0.027)))
                case let .content(content):
                    return .content(content)
                }
            }
            |> `catch` { _ -> Signal<PendingMessageUploadedContentResult?, NoError> in
                return .single(nil)
            }
        } else {
            uploadedMedia = .single(nil)
        }
    }
    return uploadedRichMessage(network: network, postbox: postbox, auxiliaryMethods: stateManager.auxiliaryMethods, messageMediaPreuploadManager: messageMediaPreuploadManager, forceReupload: forceReupload, peerId: messageId.peerId, richText: richText)
    |> mapError { _ -> RequestEditMessageInternalError in }
    |> mapToSignal { resolvedRichMessage -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> in
        return uploadedMedia
        |> mapError { _ -> RequestEditMessageInternalError in }
        |> mapToSignal { uploadedMediaResult -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> in
        var pendingMediaContent: PendingMessageUploadedContent?
        if let uploadedMediaResult = uploadedMediaResult {
            switch uploadedMediaResult {
            case let .progress(value):
                return .single(.progress(value.progress))
            case let .content(content):
                pendingMediaContent = content.content
            }
        }
        return postbox.transaction { transaction -> (Peer?, Message?, SimpleDictionary<PeerId, Peer>, (String, [Api.MessageEntity])?) in
            guard let message = transaction.getMessage(messageId) else {
                return (nil, nil, SimpleDictionary(), nil)
            }
            
            for (_, file) in inlineStickers {
                transaction.storeMediaIfNotPresent(media: file)
            }
        
            if text.isEmpty {
                for media in message.media {
                    switch media {
                        case _ as TelegramMediaImage, _ as TelegramMediaFile, _ as TelegramMediaTodo:
                            break
                        default:
                            if let _ = scheduleInfoAttribute {
                                break
                            } else {
                                return (nil, nil, SimpleDictionary(), nil)
                            }
                    }
                }
            }
        
            var peers = SimpleDictionary<PeerId, Peer>()

            if let entities = entities {
                for peerId in entities.associatedPeerIds {
                    if let peer = transaction.getPeer(peerId) {
                        peers[peer.id] = peer
                    }
                }
            }
            let pseudoReplyContent = donutgramPseudoReplyEditContent(transaction: transaction, accountPeerId: accountPeerId, message: message, text: text, entities: entities, associatedPeers: peers)
            return (transaction.getPeer(messageId.peerId), message, peers, pseudoReplyContent)
        }
        |> mapError { _ -> RequestEditMessageInternalError in }
        |> mapToSignal { peer, message, associatedPeers, pseudoReplyContent -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> in
            if let peer, let message, let inputPeer = apiInputPeer(peer) {
                var flags: Int32 = 1 << 11
                
                var apiEntities: [Api.MessageEntity]?
                if let entities {
                    apiEntities = apiTextAttributeEntities(entities, associatedPeers: associatedPeers)
                    flags |= Int32(1 << 3)
                }
                if let pseudoReplyContent {
                    apiEntities = pseudoReplyContent.1
                    flags |= Int32(1 << 3)
                }
                
                let apiRichMessage = resolvedRichMessage
                if apiRichMessage != nil {
                    flags |= Int32(1 << 23)
                }
                
                if disableUrlPreview {
                    flags |= Int32(1 << 1)
                }
                
                var inputMedia: Api.InputMedia? = nil
                if let pendingMediaContent = pendingMediaContent {
                    switch pendingMediaContent {
                        case let .media(media, _):
                            inputMedia = media
                        default:
                            break
                    }
                }
                if let _ = inputMedia {
                    flags |= Int32(1 << 14)
                }
                
                var effectiveScheduleTime: Int32?
                var effectiveScheduleRepeatPeriod: Int32?
                if messageId.namespace == Namespaces.Message.ScheduledCloud {
                    if let scheduleTime = scheduleInfoAttribute?.scheduleTime {
                        effectiveScheduleTime = scheduleTime
                    } else {
                        effectiveScheduleTime = message.timestamp
                    }
                    flags |= Int32(1 << 15)
                    
                    if let scheduleInfoAttribute {
                        effectiveScheduleRepeatPeriod = scheduleInfoAttribute.repeatPeriod ?? 0
                        flags |= Int32(1 << 18)
                    }
                }
                
                if let webpagePreviewAttribute, webpagePreviewAttribute.leadingPreview {
                    flags |= Int32(1 << 16)
                }
                if let _ = invertMediaAttribute {
                    flags |= Int32(1 << 16)
                }
                
                var quickReplyShortcutId: Int32?
                if messageId.namespace == Namespaces.Message.QuickReplyCloud {
                    quickReplyShortcutId = Int32(clamping: message.threadId ?? 0)
                    flags |= Int32(1 << 17)
                }
                
                let request: Signal<Api.Updates, MTRpcError>
                if messageId.namespace == Namespaces.Message.WelcomeMessageCloud {
                    var welcomeFlags: Int32 = (1 << 0) | (1 << 6) | (1 << 7)
                    if apiEntities != nil {
                        welcomeFlags |= (1 << 1)
                    }
                    if inputMedia != nil {
                        welcomeFlags |= (1 << 3)
                    }
                    if apiRichMessage != nil {
                        welcomeFlags |= (1 << 4)
                    }
                    if invertMediaAttribute != nil || webpagePreviewAttribute?.leadingPreview == true {
                        welcomeFlags |= (1 << 5)
                    }
                    request = network.request(Api.functions.ephemeral.editMessage(flags: welcomeFlags, peer: inputPeer, receiverId: .inputUserEmpty, id: messageId.id, message: pseudoReplyContent?.0 ?? text, media: inputMedia, entities: apiEntities, replyMarkup: nil, richMessage: apiRichMessage))
                } else {
                    request = network.request(Api.functions.messages.editMessage(flags: flags, peer: inputPeer, id: messageId.id, message: pseudoReplyContent?.0 ?? text, media: inputMedia, replyMarkup: nil, entities: apiEntities, scheduleDate: effectiveScheduleTime, scheduleRepeatPeriod: effectiveScheduleRepeatPeriod, quickReplyShortcutId: quickReplyShortcutId, richMessage: apiRichMessage))
                }

                return request
                |> map { result -> Api.Updates? in
                    return result
                }
                |> `catch` { error -> Signal<Api.Updates?, MTRpcError> in
                    if error.errorDescription == "MESSAGE_NOT_MODIFIED" {
                        return .single(nil)
                    } else {
                        return .fail(error)
                    }
                }
                |> mapError { error -> RequestEditMessageInternalError in
                    if error.errorDescription.hasPrefix("FILEREF_INVALID") || error.errorDescription.hasPrefix("FILE_REFERENCE_") {
                        return .invalidReference
                    } else if error.errorDescription.hasSuffix("_TOO_LONG") {
                        return .error(.textTooLong)
                    } else if error.errorDescription.hasPrefix("MEDIA_GROUPED_INVALID") {
                        return .error(.invalidGrouping)
                    } else if error.errorDescription.hasPrefix("CHAT_SEND_") && error.errorDescription.hasSuffix("_FORBIDDEN") {
                        return .error(.restricted)
                    }
                    return .error(.generic)
                }
                |> mapToSignal { result -> Signal<RequestEditMessageResult, RequestEditMessageInternalError> in
                    if let result = result {
                        return postbox.transaction { transaction -> RequestEditMessageResult in
                            var toMedia: Media?
                            var toRichText: RichTextMessageAttribute?
                            if let message = result.messages.first.flatMap({ StoreMessage(apiMessage: $0, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum) }) {
                                toMedia = message.media.first
                                toRichText = message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute
                            }

                            if case let .update(fromMedia) = media, let toMedia = toMedia {
                                applyMediaResourceChanges(from: fromMedia.media, to: toMedia, postbox: postbox, force: true)
                            }
                            if let richText, let toRichText {
                                applyMediaResourceChanges(from: richText, to: toRichText, postbox: postbox, force: true)
                            }
                            
                            // Donutgram: the edit went out as a pseudo-reply
                            // (donutgramPseudoReplyEditContent); the local copy keeps the typed body.
                            let donutgramLocalBody = pseudoReplyContent.map { _ in (messageId: messageId, text: text, entities: entities) }

                            switch result {
                            case let .updates(updatesData):
                                let (updates, users, chats) = (updatesData.updates, updatesData.users, updatesData.chats)
                                for update in updates {
                                    switch update {
                                    case .updateEditMessage(let data):
                                        let message = data.message
                                        let peers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: peers)

                                        if let message = StoreMessage(apiMessage: message, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum), case let .Id(id) = message.id {
                                            transaction.updateMessage(id, update: { previousMessage in
                                                var updatedFlags = message.flags
                                                var updatedLocalTags = message.localTags
                                                if previousMessage.localTags.contains(.OutgoingLiveLocation) {
                                                    updatedLocalTags.insert(.OutgoingLiveLocation)
                                                }
                                                if previousMessage.flags.contains(.Incoming) {
                                                    updatedFlags.insert(.Incoming)
                                                } else {
                                                    updatedFlags.remove(.Incoming)
                                                }

                                                var updatedMedia = message.media
                                                if let previousPaidContent = previousMessage.media.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent, case .full = previousPaidContent.extendedMedia.first {
                                                    updatedMedia = previousMessage.media
                                                }

                                                return .update(donutgramKeepingPseudoReply(previous: previousMessage, updated: message.withUpdatedLocalTags(updatedLocalTags).withUpdatedFlags(updatedFlags).withUpdatedMedia(updatedMedia), localBody: donutgramLocalBody))
                                            })
                                        }
                                    case .updateNewMessage(let data):
                                        let message = data.message
                                        let peers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: peers)

                                        if let message = StoreMessage(apiMessage: message, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum), case let .Id(id) = message.id {
                                            transaction.updateMessage(id, update: { previousMessage in
                                                var updatedFlags = message.flags
                                                var updatedLocalTags = message.localTags
                                                if previousMessage.localTags.contains(.OutgoingLiveLocation) {
                                                    updatedLocalTags.insert(.OutgoingLiveLocation)
                                                }
                                                if previousMessage.flags.contains(.Incoming) {
                                                    updatedFlags.insert(.Incoming)
                                                } else {
                                                    updatedFlags.remove(.Incoming)
                                                }

                                                var updatedMedia = message.media
                                                if let previousPaidContent = previousMessage.media.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent, case .full = previousPaidContent.extendedMedia.first {
                                                    updatedMedia = previousMessage.media
                                                }

                                                return .update(donutgramKeepingPseudoReply(previous: previousMessage, updated: message.withUpdatedLocalTags(updatedLocalTags).withUpdatedFlags(updatedFlags).withUpdatedMedia(updatedMedia), localBody: donutgramLocalBody))
                                            })
                                        }
                                    case .updateEditChannelMessage(let data):
                                        let message = data.message
                                        let peers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: peers)

                                        if let message = StoreMessage(apiMessage: message, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum), case let .Id(id) = message.id {
                                            transaction.updateMessage(id, update: { previousMessage in
                                                var updatedFlags = message.flags
                                                var updatedLocalTags = message.localTags
                                                if previousMessage.localTags.contains(.OutgoingLiveLocation) {
                                                    updatedLocalTags.insert(.OutgoingLiveLocation)
                                                }
                                                if previousMessage.flags.contains(.Incoming) {
                                                    updatedFlags.insert(.Incoming)
                                                } else {
                                                    updatedFlags.remove(.Incoming)
                                                }

                                                var updatedMedia = message.media
                                                if let previousPaidContent = previousMessage.media.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent, case .full = previousPaidContent.extendedMedia.first {
                                                    updatedMedia = previousMessage.media
                                                }

                                                return .update(donutgramKeepingPseudoReply(previous: previousMessage, updated: message.withUpdatedLocalTags(updatedLocalTags).withUpdatedFlags(updatedFlags).withUpdatedMedia(updatedMedia), localBody: donutgramLocalBody))
                                            })
                                        }
                                    case .updateNewChannelMessage(let data):
                                        let message = data.message
                                        let peers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: peers)
                                        
                                        if let message = StoreMessage(apiMessage: message, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum), case let .Id(id) = message.id {
                                            transaction.updateMessage(id, update: { previousMessage in
                                                var updatedFlags = message.flags
                                                var updatedLocalTags = message.localTags
                                                if previousMessage.localTags.contains(.OutgoingLiveLocation) {
                                                    updatedLocalTags.insert(.OutgoingLiveLocation)
                                                }
                                                if previousMessage.flags.contains(.Incoming) {
                                                    updatedFlags.insert(.Incoming)
                                                } else {
                                                    updatedFlags.remove(.Incoming)
                                                }
                                                
                                                var updatedMedia = message.media
                                                if let previousPaidContent = previousMessage.media.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent, case .full = previousPaidContent.extendedMedia.first {
                                                    updatedMedia = previousMessage.media
                                                }
                                                
                                                return .update(donutgramKeepingPseudoReply(previous: previousMessage, updated: message.withUpdatedLocalTags(updatedLocalTags).withUpdatedFlags(updatedFlags).withUpdatedMedia(updatedMedia), localBody: donutgramLocalBody))
                                            })
                                        }
                                    default:
                                        break
                                    }
                                }
                            default:
                                break
                            }
                            
                            // Donutgram: from now on server copies start with the quote this edit
                            // sent (donutgramPreservingPseudoReply). A scheduled message gets its
                            // server copy only through these updates, so it has the old body here.
                            if let pseudoReplyContent {
                                donutgramStorePseudoReplyPrefix(transaction: transaction, messageId: messageId, sentText: pseudoReplyContent.0, body: text)
                            }

                            stateManager.addUpdates(result)
                            
                            return .done(true)
                        }
                        |> mapError { _ -> RequestEditMessageInternalError in
                        }
                    } else {
                        return .single(.done(false))
                    }
                }
            } else {
                return .single(.done(false))
            }
        }
    }
    }
}

func _internal_requestEditLiveLocation(postbox: Postbox, network: Network, stateManager: AccountStateManager, messageId: MessageId, stop: Bool, coordinate: (latitude: Double, longitude: Double, accuracyRadius: Int32?)?, heading: Int32?, proximityNotificationRadius: Int32?, extendPeriod: Int32?) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> (Api.InputPeer, TelegramMediaMap)? in
        guard let inputPeer = transaction.getPeer(messageId.peerId).flatMap(apiInputPeer) else {
            return nil
        }
        guard let message = transaction.getMessage(messageId) else {
            return nil
        }
        for media in message.media {
            if let media = media as? TelegramMediaMap {
                return (inputPeer, media)
            }
        }
        return nil
    }
    |> mapToSignal { inputPeerAndMedia -> Signal<Void, NoError> in
        guard let (inputPeer, media) = inputPeerAndMedia else {
            return .complete()
        }
        let inputMedia: Api.InputMedia
        if let liveBroadcastingTimeout = media.liveBroadcastingTimeout, !stop {
            var flags: Int32 = 1 << 1
            let inputGeoPoint: Api.InputGeoPoint
            if let coordinate = coordinate {
                var geoFlags: Int32 = 0
                if let _ = coordinate.accuracyRadius {
                    geoFlags |= 1 << 0
                }
                inputGeoPoint = .inputGeoPoint(.init(flags: geoFlags, lat: coordinate.latitude, long: coordinate.longitude, accuracyRadius: coordinate.accuracyRadius.flatMap({ Int32($0) })))
            } else {
                var geoFlags: Int32 = 0
                if let _ = media.accuracyRadius {
                    geoFlags |= 1 << 0
                }
                inputGeoPoint = .inputGeoPoint(.init(flags: geoFlags, lat: media.latitude, long: media.longitude, accuracyRadius: media.accuracyRadius.flatMap({ Int32($0) })))
            }
            if let _ = heading {
                flags |= 1 << 2
            }
            if let _ = proximityNotificationRadius {
                flags |= 1 << 3
            }
            
            let period: Int32
            if let extendPeriod {
                if extendPeriod == liveLocationIndefinitePeriod {
                    period = extendPeriod
                } else {
                    period = liveBroadcastingTimeout + extendPeriod
                }
            } else {
                period = liveBroadcastingTimeout
            }
            
            inputMedia = .inputMediaGeoLive(.init(flags: flags, geoPoint: inputGeoPoint, heading: heading, period: period, proximityNotificationRadius: proximityNotificationRadius))
        } else {
            inputMedia = .inputMediaGeoLive(.init(flags: 1 << 0, geoPoint: .inputGeoPoint(.init(flags: 0, lat: media.latitude, long: media.longitude, accuracyRadius: nil)), heading: nil, period: nil, proximityNotificationRadius: nil))
        }

        return network.request(Api.functions.messages.editMessage(flags: 1 << 14, peer: inputPeer, id: messageId.id, message: nil, media: inputMedia, replyMarkup: nil, entities: nil, scheduleDate: nil, scheduleRepeatPeriod: nil, quickReplyShortcutId: nil, richMessage: nil))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Updates?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { updates -> Signal<Void, NoError> in
            if let updates = updates {
                stateManager.addUpdates(updates)
            }
            if coordinate == nil && proximityNotificationRadius == nil && extendPeriod == nil {
                return postbox.transaction { transaction -> Void in
                    transaction.updateMessage(messageId, update: { currentMessage in
                        var storeForwardInfo: StoreMessageForwardInfo?
                        if let forwardInfo = currentMessage.forwardInfo {
                            storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                        }
                        var updatedLocalTags = currentMessage.localTags
                        updatedLocalTags.remove(.OutgoingLiveLocation)
                        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: updatedLocalTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
                    })
                }
            } else {
                return .complete()
            }
        }
    }
}
