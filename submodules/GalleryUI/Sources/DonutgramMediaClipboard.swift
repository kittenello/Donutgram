import Foundation
import UIKit
import AVFoundation
import AccountContext
import TelegramCore
import SwiftSignalKit
import Pasteboard
import SaveToCameraRoll

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
