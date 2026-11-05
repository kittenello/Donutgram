import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

// Lightweight adapters for app storage and signals. The writer below is extracted unchanged from production.
enum NoError {}
protocol Disposable { func dispose() }
final class ActionDisposable: Disposable {
    var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func dispose() { let action = self.action; self.action = nil; action?() }
}
let EmptyDisposable: Disposable = ActionDisposable({})
final class Atomic<T> {
    private let lock = NSLock()
    private var value: T
    init(value: T) { self.value = value }
    func with<R>(_ f: (T) -> R) -> R { self.lock.lock(); defer { self.lock.unlock() }; return f(self.value) }
    func swap(_ value: T) -> T { self.lock.lock(); defer { self.lock.unlock() }; let previous = self.value; self.value = value; return previous }
}
final class Subscriber<T, E> {
    let next: (T) -> Void
    let completed: () -> Void
    init(next: @escaping (T) -> Void, completed: @escaping () -> Void) { self.next = next; self.completed = completed }
    func putNext(_ value: T) { self.next(value) }
    func putCompletion() { self.completed() }
}
final class Signal<T, E> {
    let generator: (Subscriber<T, E>) -> Disposable
    init(_ generator: @escaping (Subscriber<T, E>) -> Disposable) { self.generator = generator }
    func start(next: @escaping (T) -> Void, completed: @escaping () -> Void) -> Disposable {
        return self.generator(Subscriber(next: next, completed: completed))
    }
}
struct UIImage {
    let cgImage: CGImage?
    func jpegData(compressionQuality: Double) -> Data? {
        guard let cgImage else { return nil }
        let data = CFDataCreateMutable(nil, 0)!
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
struct LocalFileMediaResource {
    let fileId: Int64
    var id: Int64 { self.fileId }
}
enum Namespaces { enum Media { static let LocalFile: Int32 = 8 } }
enum EngineMedia { struct Id { let namespace: Int32; let id: Int64 } }
enum EngineMediaResource { struct Id { let value: Int64; init(_ value: Int64) { self.value = value } } }
struct PixelDimensions { let size: CGSize; init(_ size: CGSize) { self.size = size } }
struct TelegramMediaImageRepresentation {
    let resource: LocalFileMediaResource
    init(dimensions: PixelDimensions, resource: LocalFileMediaResource, progressiveSizes: [Never], immediateThumbnailData: Data?, hasVideo: Bool, isPersonal: Bool) { self.resource = resource }
}
struct VideoFlags: OptionSet {
    let rawValue: Int
    static let isSilent = Self(rawValue: 1)
    static let supportsStreaming = Self(rawValue: 2)
}
enum FileAttribute {
    case FileName(fileName: String)
    case Video(duration: Double, size: PixelDimensions, flags: VideoFlags, preloadSize: Int?, coverTime: Double?, videoCodec: String?)
}
struct TelegramMediaFile {
    let resource: LocalFileMediaResource
    let mimeType: String
    let attributes: [FileAttribute]
    let previews: [TelegramMediaImageRepresentation]
    init(fileId: EngineMedia.Id, partialReference: Never?, resource: LocalFileMediaResource, previewRepresentations: [TelegramMediaImageRepresentation], videoThumbnails: [Never], immediateThumbnailData: Data?, mimeType: String, size: Int64, attributes: [FileAttribute], alternativeRepresentations: [Never]) {
        self.resource = resource; self.mimeType = mimeType; self.attributes = attributes; self.previews = previewRepresentations
    }
}
enum AnyMediaReference { case standalone(media: TelegramMediaFile) }
final class Resources {
    var files: [Int64: Data] = [:]
    func storeResourceData(id: EngineMediaResource.Id, data: Data) { self.files[id.value] = data }
}
final class Engine { let resources = Resources() }
final class AccountContext { let engine = Engine() }
final class EngineTempBox {
    struct File { let path: String }
    static let shared = EngineTempBox()
    func tempFile(fileName: String) -> File {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dg-sticker-video-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return File(path: directory.appendingPathComponent(fileName).path)
    }
    func dispose(_ file: File) { try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path).deletingLastPathComponent()) }
}
private let donutgramStickerExportQueue = DispatchQueue(label: "sticker-video-test")

// PRODUCTION WRITER

let context = AccountContext()
let size = CGSize(width: 64, height: 64)
let bitmap = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
bitmap.fill(CGRect(origin: .zero, size: size))
let image = UIImage(cgImage: bitmap.makeImage()!)
let encoded = DispatchSemaphore(value: 0)
var result: TelegramMediaFile?
var samples = 0
let disposable = donutgramStickerVideo(context: context, size: size, frameCount: 2, nextFrame: {
    samples += 1
    return (image, 0.5)
}).start(next: { reference in
    if case let .standalone(media: file)? = reference { result = file }
}, completed: { encoded.signal() })
precondition(encoded.wait(timeout: .now() + 20) == .success, "static sticker encoding must finish")
guard let file = result, let data = context.engine.resources.files[file.resource.id] else { fatalError("expected an encoded video") }
precondition(samples == 2 && file.mimeType == "video/mp4")
precondition(file.previews.count == 1, "the video has a preview")
precondition(file.attributes.contains { attribute in
    if case let .Video(duration, _, flags, _, _, _) = attribute { return duration == 1.0 && flags.contains(.isSilent) }
    return false
}, "outgoing media declares a one-second silent video")
let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
try data.write(to: output)
defer { try? FileManager.default.removeItem(at: output) }
let inspected = DispatchSemaphore(value: 0)
Task.detached {
    do {
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        precondition(abs(duration.seconds - 1.0) < 0.02, "the MP4 itself must last one second")
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        precondition(video.count == 1 && audio.isEmpty, "a playable video without an audio track")
        let generator = AVAssetImageGenerator(asset: asset)
        let (frame, _) = try await generator.image(at: .zero)
        precondition(frame.width == 64 && frame.height == 64, "the encoded first frame can be decoded")
    } catch { fatalError("invalid MP4: \(error)") }
    inspected.signal()
}
precondition(inspected.wait(timeout: .now() + 20) == .success, "MP4 inspection must finish")
disposable.dispose()

let failed = DispatchSemaphore(value: 0)
var didFail = false
let failureDisposable = donutgramStickerVideo(context: context, size: size, frameCount: 2, nextFrame: { nil }).start(next: { reference in
    if case nil = reference { didFail = true }
}, completed: { failed.signal() })
precondition(failed.wait(timeout: .now() + 20) == .success && didFail, "a bad frame finishes with failure")
failureDisposable.dispose()
print("static sticker MP4 duration, playback, preview and encoding failure checks passed")
