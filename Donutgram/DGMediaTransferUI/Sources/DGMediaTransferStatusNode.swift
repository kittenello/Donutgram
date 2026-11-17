import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import DGSimpleSettings
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting

public final class DGMediaTransferStatusNode: ASDisplayNode {
    public var sizeUpdated: ((CGSize) -> Void)?
    public var isTransferVisible: Bool = true {
        didSet {
            if self.isTransferVisible != oldValue { self.render() }
        }
    }
    private let textNode = ImmediateTextNode()
    private let disposable = MetaDisposable()
    private var timer: SwiftSignalKit.Timer?
    private var rate = DGMediaTransferRate()
    private var key: String?
    private var size: Int64?
    private var width: CGFloat = 160.0
    private var status: EngineMediaResource.FetchStatus?
    private var pending: PendingMessageStatus?
    private var presentationData: ChatPresentationData?

    public override init() {
        super.init()
        self.isUserInteractionEnabled = false
        self.backgroundColor = UIColor(white: 0.0, alpha: 0.65)
        self.cornerRadius = 6.0
        self.textNode.maximumNumberOfLines = 2
        self.addSubnode(self.textNode)
        self.isHidden = true
    }

    deinit {
        self.disposable.dispose()
        self.timer?.invalidate()
    }

    public func update(context: AccountContext, message: EngineMessage, file: TelegramMediaFile?, presentationData: ChatPresentationData, width: CGFloat) {
        self.presentationData = presentationData
        self.width = max(1.0, width)
        self.size = file?.size ?? file?.resource.size
        let enabled = !presentationData.isPreview && !message.containsSecretMedia
        let key = enabled ? file.map { "\(context.account.peerId)-\(message.id)-\($0.resource.id.stringRepresentation)-\(message.flags.isSending)" } : nil
        if self.key != key {
            self.key = key
            self.rate.reset()
            self.status = nil
            self.pending = nil
            self.disposable.set(nil)
            if let file, key != nil {
                let pending: Signal<PendingMessageStatus?, NoError>
                if message.flags.isSending {
                    pending = context.account.pendingMessageManager.pendingMessageStatus(message.id) |> map { $0.0 }
                } else {
                    pending = .single(nil)
                }
                self.disposable.set((combineLatest(context.engine.resources.status(resource: EngineMediaResource(file.resource)), pending)
                |> deliverOnMainQueue).start(next: { [weak self] status, pending in
                    guard let self, self.key == key else { return }
                    self.status = status
                    self.pending = pending
                    self.render()
                }))
            }
        }
        self.render()
    }

    private func render() {
        guard self.isTransferVisible, let presentationData, let key else {
            self.hide()
            return
        }
        var progress: Float
        let isActive: Bool
        if let pending {
            progress = pending.progress.phaseProgress
            isActive = pending.isRunning
        } else if let status, case let .Fetching(active, value) = status {
            progress = value
            isActive = active
        } else {
            self.hide()
            return
        }
        guard DGSimpleSettings.shared.shouldShowMediaTransferDetails(isProcessing: self.pending?.progress.phase == .processing) else {
            self.hide()
            return
        }
        progress = progress.isFinite ? min(1.0, max(0.0, progress)) : 0.0
        if !isActive { self.rate.reset() }
        let text: String
        if self.pending?.progress.phase == .processing {
            self.rate.reset()
            text = dgLocalized("Обработка видео", languageCode: presentationData.strings.baseLanguageCode) + " · \(Int(progress * 100.0))%"
        } else if let size = self.size, size > 0, size != .max {
            let bytes = DGMediaTransferRate.transferredBytes(total: size, progress: progress)
            let rate = self.rate.update(key: key, bytes: bytes, timestamp: CACurrentMediaTime())
            let formatting = DataSizeStringFormatting(chatPresentationData: presentationData)
            let speed = rate.map { dataSizeString($0, forceDecimal: true, formatting: formatting) } ?? "—"
            text = "\(Int(progress * 100.0))% · \(speed)/s"
        } else {
            text = "\(Int(progress * 100.0))% · —/s"
        }
        self.isHidden = false
        self.textNode.attributedText = NSAttributedString(string: text, font: Font.with(size: 11.0, design: .regular, weight: .regular, traits: [.monospacedNumbers]), textColor: .white)
        let size = self.textNode.updateLayout(CGSize(width: max(1.0, self.width - 12.0), height: 48.0))
        self.textNode.frame = CGRect(origin: CGPoint(x: 6.0, y: 3.0), size: size)
        self.sizeUpdated?(CGSize(width: size.width + 12.0, height: size.height + 6.0))
        if isActive && self.timer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 0.25, repeat: true, completion: { [weak self] in
                self?.render()
            }, queue: .mainQueue())
            self.timer = timer
            timer.start()
        } else if !isActive {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func hide() {
        self.isHidden = true
        self.rate.reset()
        self.timer?.invalidate()
        self.timer = nil
    }
}
