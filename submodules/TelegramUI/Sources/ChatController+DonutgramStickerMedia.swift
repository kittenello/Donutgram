import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AnimationCache
import EmojiTextAttachmentView

private let donutgramStickerExportQueue = DispatchQueue(label: "donutgram.sticker-export", qos: .userInitiated)

private func donutgramStickerFrameImage(_ frame: AnimationCacheItemFrame) -> UIImage? {
    guard case let .rgba(data, width, height, bytesPerRow) = frame.format,
        width > 0, height > 0, bytesPerRow >= width * 4, data.count >= height * bytesPerRow,
        let context = DrawingContext(size: CGSize(width: width, height: height), scale: 1.0, opaque: false, bytesPerRow: bytesPerRow) else {
        return nil
    }
    data.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress {
            memcpy(context.bytes, base, height * bytesPerRow)
        }
    }
    guard let image = context.generateImage()?.cgImage else {
        return nil
    }
    return generateImage(CGSize(width: width, height: height), opaque: true, scale: 1.0, rotatedContext: { size, context in
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
    })
}

private func donutgramStickerVideo(context: AccountContext, item: AnimationCacheItem, size: CGSize) -> Signal<AnyMediaReference?, NoError> {
    return Signal { subscriber in
        let temporary = EngineTempBox.shared.tempFile(fileName: "sticker-video.mp4")
        guard let writer = try? AVAssetWriter(outputURL: URL(fileURLWithPath: temporary.path), fileType: .mp4) else {
            temporary.dispose()
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else {
            temporary.dispose()
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        writer.add(input)
        guard writer.startWriting() else {
            temporary.dispose()
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        writer.startSession(atSourceTime: .zero)
        let cancelled = Atomic<Bool>(value: false)
        var index = 0
        var duration = 0.0
        var finished = false
        var thumbnail: Data?
        item.reset()
        input.requestMediaDataWhenReady(on: donutgramStickerExportQueue) {
            guard !finished, !cancelled.with({ $0 }) else {
                return
            }
            while input.isReadyForMoreMediaData && index < item.numFrames {
                let appended = autoreleasepool { () -> Bool in
                    guard let frame = item.advance(advance: .frames(1), requestedFormat: .rgba)?.frame,
                        let image = donutgramStickerFrameImage(frame),
                        let cgImage = image.cgImage,
                        let pool = adaptor.pixelBufferPool else {
                        return false
                    }
                    if thumbnail == nil {
                        thumbnail = image.jpegData(compressionQuality: 0.7)
                    }
                    var optionalBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess, let buffer = optionalBuffer else {
                        return false
                    }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let bitmap = CGContext(
                        data: CVPixelBufferGetBaseAddress(buffer),
                        width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    ) else {
                        return false
                    }
                    bitmap.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: duration, preferredTimescale: 60_000)) else {
                        return false
                    }
                    duration += frame.duration.isFinite && frame.duration > 0 ? frame.duration : 1.0 / 30.0
                    return true
                }
                guard appended, duration <= 60.0 else {
                    finished = true
                    writer.cancelWriting()
                    temporary.dispose()
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                index += 1
                if cancelled.with({ $0 }) {
                    return
                }
            }
            if index == item.numFrames {
                finished = true
                writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60_000))
                input.markAsFinished()
                writer.finishWriting {
                    defer { temporary.dispose() }
                    guard !cancelled.with({ $0 }), writer.status == .completed,
                        let data = try? Data(contentsOf: URL(fileURLWithPath: temporary.path)) else {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                    var previews: [TelegramMediaImageRepresentation] = []
                    if let thumbnail {
                        let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnail)
                        previews.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(size), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                    }
                    let file = TelegramMediaFile(
                        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: resource.fileId),
                        partialReference: nil, resource: resource, previewRepresentations: previews,
                        videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: Int64(data.count),
                        attributes: [
                            .FileName(fileName: "sticker-video.mp4"),
                            .Video(duration: duration, size: PixelDimensions(size), flags: [.isSilent, .supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil)
                        ], alternativeRepresentations: []
                    )
                    subscriber.putNext(.standalone(media: file))
                    subscriber.putCompletion()
                }
            }
        }
        return ActionDisposable {
            let _ = cancelled.swap(true)
            donutgramStickerExportQueue.async {
                if writer.status == .writing {
                    writer.cancelWriting()
                }
                temporary.dispose()
            }
        }
    }
}

private func donutgramStickerMedia(context: AccountContext, peerId: EnginePeer.Id, file: FileMediaReference) -> Signal<AnyMediaReference?, NoError> {
    let sourceSize = file.media.dimensions?.cgSize ?? CGSize(width: 512.0, height: 512.0)
    let dimensions = (sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize : CGSize(width: 512.0, height: 512.0)).aspectFitted(CGSize(width: 512.0, height: 512.0))
    let size = CGSize(width: CGFloat(max(2, Int(dimensions.width) / 2 * 2)), height: CGFloat(max(2, Int(dimensions.height) / 2 * 2)))
    let fetch = animationCacheFetchFile(context: context, userLocation: .peer(peerId), userContentType: .sticker, resource: file.abstract.resourceReference(file.media.resource), type: AnimationCacheAnimationType(file: file.media), keyframeOnly: false, customColor: nil)
    return context.animationCache.get(sourceId: file.media.resource.id.stringRepresentation, size: size, fetch: fetch)
    |> filter { $0.isFinal }
    |> take(1)
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> mapToSignal { result -> Signal<AnyMediaReference?, NoError> in
        guard let item = result.item, item.numFrames > 0, item.numFrames <= 1800 else {
            return .single(nil)
        }
        if file.media.isAnimatedSticker || file.media.isVideoSticker {
            return donutgramStickerVideo(context: context, item: item, size: size)
        }
        item.reset()
        guard let frame = item.advance(advance: .frames(1), requestedFormat: .rgba)?.frame,
            let image = donutgramStickerFrameImage(frame),
            let data = image.jpegData(compressionQuality: 0.95) else {
            return .single(nil)
        }
        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
        let imageMedia = TelegramMediaImage(
            imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: resource.fileId),
            representations: [TelegramMediaImageRepresentation(dimensions: PixelDimensions(size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)],
            immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: []
        )
        return .single(.standalone(media: imageMedia))
    }
    |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

func donutgramPrepareStickerMedia(context: AccountContext, peer: EngineRawPeer?, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage]?, NoError> {
    guard let peer, donutgramCanSendStickerAsMedia(peer: peer), messages.contains(where: { message in
        if case let .message(_, _, _, reference, _, _, _, _, _, _) = message, let file = reference?.media as? TelegramMediaFile {
            return file.isSticker
        }
        return false
    }) else {
        return .single(messages)
    }
    return combineLatest(messages.map { message -> Signal<EnqueueMessage?, NoError> in
        guard case let .message(text, attributes, inlineStickers, reference?, threadId, replyId, storyId, groupingKey, correlationId, _) = message,
            let fileReference = reference.concrete(TelegramMediaFile.self), fileReference.media.isSticker else {
            return .single(message)
        }
        let file = fileReference.media
        guard donutgramCanSendStickerAsMedia(peer: peer, file: file) else {
            return .single(nil)
        }
        return donutgramStickerMedia(context: context, peerId: peer.id, file: fileReference)
        |> map { converted -> EnqueueMessage? in
            guard let converted else {
                return nil
            }
            let attributes = attributes.filter { !($0 is OutgoingChatContextResultMessageAttribute) && !($0 is InlineBotMessageAttribute) && !($0 is EmojiSearchQueryMessageAttribute) }
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: converted, threadId: threadId, replyToMessageId: replyId, replyToStoryId: storyId, localGroupingKey: groupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
        }
    })
    |> map { results -> [EnqueueMessage]? in
        let messages = results.compactMap { $0 }
        return messages.count == results.count ? messages : nil
    }
}
