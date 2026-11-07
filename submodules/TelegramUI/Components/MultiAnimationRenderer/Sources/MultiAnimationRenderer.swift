import Foundation
import UIKit
import SwiftSignalKit
import Display
import AnimationCache

public protocol MultiAnimationRenderer: AnyObject {
    func add(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, unique: Bool, size: CGSize, fetch: @escaping (AnimationCacheFetchOptions) -> Disposable) -> Disposable
    func loadFirstFrameSynchronously(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, size: CGSize) -> Bool
    func loadFirstFrame(target: MultiAnimationRenderTarget, cache: AnimationCache, itemId: String, size: CGSize, fetch: ((AnimationCacheFetchOptions) -> Disposable)?, completion: @escaping (Bool, Bool) -> Void) -> Disposable
    func loadFirstFrameAsImage(cache: AnimationCache, itemId: String, size: CGSize, fetch: ((AnimationCacheFetchOptions) -> Disposable)?, completion: @escaping (CGImage?) -> Void) -> Disposable
    func setFrameIndex(itemId: String, size: CGSize, frameIndex: Int, placeholder: UIImage)
}

private var nextRenderTargetId: Int64 = 1

open class MultiAnimationRenderTarget: SimpleLayer {
    public let id: Int64
    public var numFrames: Int?

    public let deinitCallbacks = Bag<() -> Void>()
    public let updateStateCallbacks = Bag<() -> Void>()

    private var requestedAnimation: Bool = false
    private var powerSavingObserver: NSObjectProtocol?
    public final var shouldBeAnimating: Bool {
        get { return self.requestedAnimation && !isEnhancedPowerSavingEnabled }
        set {
            if self.requestedAnimation != newValue {
                self.requestedAnimation = newValue
                for f in self.updateStateCallbacks.copyItems() {
                    f()
                }
            }
        }
    }

    public var blurredRepresentationBackgroundColor: UIColor?
    public var blurredRepresentationTarget: CALayer? {
        didSet {
            if self.blurredRepresentationTarget !== oldValue {
                for f in self.updateStateCallbacks.copyItems() {
                    f()
                }
            }
        }
    }

    public override init() {
        assert(Thread.isMainThread)

        self.id = nextRenderTargetId
        nextRenderTargetId += 1

        super.init()
        self.observePowerSaving()
    }

    public override init(layer: Any) {
        guard let layer = layer as? MultiAnimationRenderTarget else {
            preconditionFailure()
        }

        self.id = layer.id

        super.init(layer: layer)
        self.observePowerSaving()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let powerSavingObserver = self.powerSavingObserver {
            NotificationCenter.default.removeObserver(powerSavingObserver)
        }
        for f in self.deinitCallbacks.copyItems() {
            f()
        }
    }

    open func updateDisplayPlaceholder(displayPlaceholder: Bool) {
    }

    private func observePowerSaving() {
        self.powerSavingObserver = NotificationCenter.default.addObserver(forName: enhancedPowerSavingDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            for update in self.updateStateCallbacks.copyItems() {
                update()
            }
        }
    }

    open func transitionToContents(_ contents: AnyObject, didLoop: Bool) {
    }
}
