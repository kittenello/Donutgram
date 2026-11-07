import Foundation
import UIKit
import UIKitRuntimeUtils
import SwiftSignalKit

public let enhancedPowerSavingDidChangeNotification = Notification.Name("donutgram.enhancedPowerSaving.didChange")

public var isEnhancedPowerSavingEnabled: Bool {
    return getEnhancedPowerSavingEnabled()
}

public func enhancedPowerSavingState() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: enhancedPowerSavingDidChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(isEnhancedPowerSavingEnabled)
        }
        subscriber.putNext(isEnhancedPowerSavingEnabled)
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

public func updateEnhancedPowerSaving(_ enabled: Bool) {
    precondition(Thread.isMainThread)
    guard enabled != isEnhancedPowerSavingEnabled else {
        return
    }
    setEnhancedPowerSavingEnabled(enabled)
    if enabled {
        func finishAnimations(_ layer: CALayer) {
            for key in layer.animationKeys() ?? [] {
                if let animation = layer.animation(forKey: key) {
                    if animation.delegate == nil {
                        layer.add(animationForEnhancedPowerSaving(animation), forKey: key)
                    }
                }
            }
            for child in layer.sublayers ?? [] {
                finishAnimations(child)
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            if let scene = scene as? UIWindowScene {
                for window in scene.windows {
                    finishAnimations(window.layer)
                }
            }
        }
    }
    NotificationCenter.default.post(name: enhancedPowerSavingDidChangeNotification, object: nil)
}
