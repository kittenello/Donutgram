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

/// The files of every saved deleted message of the account. Messages are read a few hundred
/// per transaction, so a large store does not hold the Postbox queue for long.
func donutgramPreservedMessageResourceIds(postbox: Postbox) -> Signal<Set<MediaResourceId>, NoError> {
    return postbox.transaction { transaction -> [MessageId] in
        return transaction.getMessageIdsWithLocalTag(.donutgramDeleted)
    }
    |> mapToSignal { messageIds -> Signal<Set<MediaResourceId>, NoError> in
        let chunkSize = 256
        var signal: Signal<Set<MediaResourceId>, NoError> = .single(Set())
        var chunkStart = 0
        while chunkStart < messageIds.count {
            let chunk = messageIds[chunkStart ..< min(chunkStart + chunkSize, messageIds.count)]
            chunkStart += chunkSize
            signal = signal
            |> mapToSignal { resourceIds -> Signal<Set<MediaResourceId>, NoError> in
                return postbox.transaction { transaction -> Set<MediaResourceId> in
                    var resourceIds = resourceIds
                    for id in chunk {
                        if let message = transaction.getMessage(id) {
                            donutgramAddMessageResourceIds(message: message, to: &resourceIds)
                        }
                    }
                    return resourceIds
                }
            }
        }
        return signal
    }
}
