import Foundation
import CoreGraphics
import ImageIO

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
protocol MediaResource { var id: Int64 { get }; var size: Int64? { get } }
class FixtureResource: MediaResource { let id: Int64; var size: Int64? { return nil }; init(_ id: Int64) { self.id = id } }
final class CloudPeerPhotoSizeMediaResource: FixtureResource {}
final class CloudPhotoSizeMediaResource: FixtureResource {}
final class CloudFileMediaResource: FixtureResource {}
final class CloudDocumentMediaResource: FixtureResource {}
final class SecretFileMediaResource: FixtureResource {}
final class LocalFileMediaResource: FixtureResource {
    let isSecretRelated: Bool
    init(_ id: Int64, secret: Bool = false) { self.isSecretRelated = secret; super.init(id) }
}
struct PixelDimensions { let width: Int32; let height: Int32 }
struct TelegramMediaImageRepresentation {
    let dimensions: PixelDimensions
    let resource: MediaResource
    init(_ resource: MediaResource, _ side: Int32) {
        self.resource = resource; self.dimensions = PixelDimensions(width: side, height: side)
    }
}
protocol Media {}
struct TelegramMediaImage: Media {
    let representations: [TelegramMediaImageRepresentation]
    var video: TelegramMediaFile? = nil
}
struct TelegramMediaFile: Media {
    let resource: MediaResource
    let size: Int64? = 20
    let mimeType = "video/mp4"
    var previewRepresentations: [TelegramMediaImageRepresentation] = []
    var videoThumbnails: [TelegramMediaImageRepresentation] = []
}
struct TelegramMediaPaidContent: Media {
    enum Extended { case full(Media), preview }
    let extendedMedia: [Extended]
}
func smallestImageRepresentation(_ values: [TelegramMediaImageRepresentation]) -> TelegramMediaImageRepresentation? {
    return values.min { $0.dimensions.width < $1.dimensions.width }
}
func largestImageRepresentation(_ values: [TelegramMediaImageRepresentation]) -> TelegramMediaImageRepresentation? {
    return values.max { $0.dimensions.width < $1.dimensions.width }
}
final class MediaBox {
    enum KeepDuration { case general }
    var values: [Int64: Data] = [:]
    var writes: [Int64] = []
    func copyResourceData(from: Int64, to: Int64) {
        if let data = self.values[from] { self.values[to] = data; self.writes.append(to) }
    }
    func moveResourceData(from: Int64, to: Int64) {
        if let data = self.values.removeValue(forKey: from) { self.values[to] = data; self.writes.append(to) }
    }
    func cachedRepresentationCompletePath(_ id: Int64, keepDuration: KeepDuration, representationId: String) -> String {
        return FileManager.default.temporaryDirectory.appendingPathComponent("absent-frame-" + UUID().uuidString).path
    }
}
final class Postbox { let mediaBox = MediaBox() }
struct MediaResourceData { let path: String; let complete: Bool }

// PRODUCTION_HELPERS

let sourceBytes = Data("original avatar JPEG".utf8)
for resource in [CloudPeerPhotoSizeMediaResource(1), CloudPhotoSizeMediaResource(1)] as [MediaResource] {
    let box = Postbox()
    box.mediaBox.values[resource.id] = sourceBytes
    let old = TelegramMediaImage(representations: [.init(resource, 640)])
    let new = TelegramMediaImage(representations: [.init(CloudPhotoSizeMediaResource(2), 640)])
    applyMediaResourceChanges(from: old, to: new, postbox: box, force: true)
    check(box.mediaBox.writes.isEmpty, "a re-uploaded cloud photo must not seed either the smallest or largest server resource with its old bytes")
    check(box.mediaBox.values[1] == sourceBytes && box.mediaBox.values[2] == nil, "preserve the original avatar cache and let the new photo download")
}
do {
    let box = Postbox()
    box.mediaBox.values[10] = sourceBytes
    box.mediaBox.values[11] = Data("generated thumbnail".utf8)
    let old = TelegramMediaImage(representations: [.init(LocalFileMediaResource(11), 100), .init(CloudPhotoSizeMediaResource(10), 640)])
    let new = TelegramMediaImage(representations: [.init(CloudPhotoSizeMediaResource(20), 100), .init(CloudPhotoSizeMediaResource(21), 640)])
    applyMediaResourceChanges(from: old, to: new, postbox: box, force: false)
    check(box.mediaBox.writes == [20], "a locally generated thumbnail can migrate without poisoning the progressive full-size photo")
    check(box.mediaBox.values[10] == sourceBytes && box.mediaBox.values[21] == nil, "the full server encoding remains separate")
}
do {
    let box = Postbox()
    box.mediaBox.values[30] = sourceBytes
    let old = TelegramMediaImage(representations: [.init(LocalFileMediaResource(30), 640)])
    let new = TelegramMediaImage(representations: [.init(CloudPhotoSizeMediaResource(31), 640)])
    applyMediaResourceChanges(from: old, to: new, postbox: box, force: false)
    check(box.mediaBox.values[31] == sourceBytes, "normal local photo uploads still reuse their data")
}
do {
    let box = Postbox()
    box.mediaBox.values[40] = sourceBytes
    let photo = TelegramMediaImage(representations: [.init(LocalFileMediaResource(40), 640)])
    applyMediaResourceChanges(from: photo, to: photo, postbox: box, force: false)
    check(box.mediaBox.writes.isEmpty && box.mediaBox.values[40] == sourceBytes, "sharing a resource id must never move its data over itself")
    let oldFile = TelegramMediaFile(resource: CloudDocumentMediaResource(40))
    let newFile = TelegramMediaFile(resource: CloudDocumentMediaResource(41))
    applyMediaResourceChanges(from: oldFile, to: newFile, postbox: box, force: false)
    check(box.mediaBox.values[40] == sourceBytes && box.mediaBox.values[41] == sourceBytes, "video/document copying is unchanged")
}

let bitmap = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 64, width: 128, height: 64))
let encoded = CFDataCreateMutable(nil, 0)!
let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
check(CGImageDestinationFinalize(destination), "create a complete avatar JPEG")
let jpeg = encoded as Data
let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
try jpeg.write(to: path)
defer { try? FileManager.default.removeItem(at: path) }
let serverProgressiveSize = jpeg.count / 2
check(serverProgressiveSize < jpeg.count, "the new server encoding can advertise a different scan size")
guard let complete = completePhotoResourceData(MediaResourceData(path: path.path, complete: true)) else { fatalError("expected cached photo") }
check(complete == jpeg && complete.count > serverProgressiveSize, "cached complete photos use the entire JPEG, never an advertised progressive prefix")
let source = CGImageSourceCreateWithData(complete as CFData, nil)!
check(CGImageSourceGetStatus(source) == .statusComplete, "the complete JPEG retains its end marker")
check(CGImageSourceCreateImageAtIndex(source, 0, nil)?.height == 128, "the bottom of the image can be decoded")
check(completePhotoResourceData(MediaResourceData(path: path.path, complete: false)) == nil, "a partially downloaded photo keeps the progressive-loading path")
check(completePhotoResourceData(MediaResourceData(path: path.path + ".missing", complete: true)) == nil, "a missing cache file falls back to progressive loading")
print("avatar share cache migration and complete JPEG decoding checks passed")
