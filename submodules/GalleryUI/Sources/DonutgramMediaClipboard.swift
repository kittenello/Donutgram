import Foundation
import UIKit
import AVFoundation
import ImageIO
import AccountContext
import TelegramCore
import SwiftSignalKit
import Pasteboard
import SaveToCameraRoll

private func donutgramImageMetadata(_ path: String) -> String? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
        return nil
    }

    let fields: [(CFString, String)] = [
        (kCGImagePropertyPixelWidth, "ширина"),
        (kCGImagePropertyPixelHeight, "высота"),
        (kCGImagePropertyTIFFMake, "камера"),
        (kCGImagePropertyTIFFModel, "модель"),
        (kCGImagePropertyTIFFSoftware, "программа"),
        (kCGImagePropertyExifDateTimeOriginal, "дата съёмки"),
        (kCGImagePropertyExifLensModel, "объектив"),
        (kCGImagePropertyExifFocalLength, "фокусное расстояние"),
        (kCGImagePropertyExifExposureTime, "выдержка"),
        (kCGImagePropertyExifFNumber, "диафрагма"),
        (kCGImagePropertyExifISOSpeedRatings, "iso"),
        (kCGImagePropertyGPSLatitude, "широта"),
        (kCGImagePropertyGPSLongitude, "долгота")
    ]

    var result: [String] = []
    for (key, title) in fields {
        if let value = properties[key] {
            result.append("\(title): \(value)")
        }
    }
    return result.isEmpty ? nil : result.joined(separator: "\n")
}

private func donutgramCopyFetchedImage(path: String) -> Bool {
    guard let image = UIImage(contentsOfFile: path) else {
        return false
    }
    UIPasteboard.general.image = image
    return true
}

private func donutgramCopyFetchedVideoFrame(path: String, timestamp: Double) -> Bool {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    guard let image = try? generator.copyCGImage(at: CMTime(seconds: max(timestamp, 0.0), preferredTimescale: 600), actualTime: nil) else {
        return false
    }
    UIPasteboard.general.image = UIImage(cgImage: image)
    return true
}

func donutgramCopyImage(context: AccountContext, mediaReference: AnyMediaReference, completion: @escaping (Bool) -> Void) -> Disposable {
    return (fetchMediaData(context: context, userLocation: .other, mediaReference: mediaReference)
    |> deliverOnMainQueue).start(next: { value, _ in
        guard case let .data(data) = value, data.isComplete else {
            return
        }
        completion(donutgramCopyFetchedImage(path: data.path))
    })
}

func donutgramCopyVideoFrame(context: AccountContext, mediaReference: AnyMediaReference, timestamp: Double = 0.0, completion: @escaping (Bool) -> Void) -> Disposable {
    return (fetchMediaData(context: context, userLocation: .other, mediaReference: mediaReference)
    |> deliverOnMainQueue).start(next: { value, _ in
        guard case let .data(data) = value, data.isComplete else {
            return
        }
        completion(donutgramCopyFetchedVideoFrame(path: data.path, timestamp: timestamp))
    })
}

func donutgramCopyImageMetadata(context: AccountContext, mediaReference: AnyMediaReference, completion: @escaping (Bool) -> Void) -> Disposable {
    return (fetchMediaData(context: context, userLocation: .other, mediaReference: mediaReference)
    |> deliverOnMainQueue).start(next: { value, _ in
        guard case let .data(data) = value, data.isComplete, let metadata = donutgramImageMetadata(data.path) else {
            return
        }
        UIPasteboard.general.string = metadata
        completion(true)
    })
}
