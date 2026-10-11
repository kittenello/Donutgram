import Foundation
import UIKit
import AVFoundation
import DeviceModel
import Camera

func legacyIsDualCameraSupported(forRoundVideo: Bool) -> Bool {
    if #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported && !DeviceModel.current.isIpad {
        // Donutgram: the round-video MultiCam path uses separate physical front/back cameras.
        // An exclusive session enables the rear virtual camera to switch lenses
        // down to 0.5×, independently of Low Power Mode. Position flips still use
        // the existing single-camera recording path.
        if forRoundVideo, AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            return false
        }
        if forRoundVideo && (ProcessInfo.processInfo.isLowPowerModeEnabled || DeviceModel.current == .iPhoneXR) {
            return false
        }
        return true
    } else {
        return false
    }
}

public final class LegacyCameraImpl: CameraImpl {
    public static let shared = LegacyCameraImpl()

    private init() {
    }

    public var isIpad: Bool {
        return DeviceModel.current.isIpad
    }

    public func isDualCameraSupported(forRoundVideo: Bool) -> Bool {
        return legacyIsDualCameraSupported(forRoundVideo: forRoundVideo)
    }

    public func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?
    ) -> CameraProtocol {
        let legacyPreviewView: LegacyCameraSimplePreviewView?
        if let previewView {
            guard let previewView = previewView as? LegacyCameraSimplePreviewView else {
                preconditionFailure()
            }
            legacyPreviewView = previewView
        } else {
            legacyPreviewView = nil
        }

        let legacySecondaryPreviewView: LegacyCameraSimplePreviewView?
        if let secondaryPreviewView {
            guard let secondaryPreviewView = secondaryPreviewView as? LegacyCameraSimplePreviewView else {
                preconditionFailure()
            }
            legacySecondaryPreviewView = secondaryPreviewView
        } else {
            legacySecondaryPreviewView = nil
        }

        return LegacyCamera(
            configuration: configuration,
            previewView: legacyPreviewView,
            secondaryPreviewView: legacySecondaryPreviewView
        )
    }

    public func makeCameraSimplePreviewView(frame: CGRect, main: Bool, roundVideo: Bool) -> CameraSimplePreviewView {
        return LegacyCameraSimplePreviewView(frame: frame, main: main, roundVideo: roundVideo)
    }
}
