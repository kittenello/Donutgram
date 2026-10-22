import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import WallpaperBackgroundNode

/// Read-only snapshots. These are local revisions; opening this screen never sends a message.
public func donutgramEditHistoryController(context: AccountContext, revisions: [DonutgramMessageRevision], currentText: String, currentTimestamp: Int32, incoming: Bool) -> ViewController {
    let snapshots = (revisions + [DonutgramMessageRevision(text: currentText, timestamp: currentTimestamp)]).map { revision in
        return DonutgramMessageRevision(text: revision.text.isEmpty ? "‹пустое сообщение›" : revision.text, timestamp: revision.timestamp)
    }
    return DonutgramEditHistoryController(context: context, snapshots: snapshots, incoming: incoming)
}

private final class DonutgramEditHistoryController: ViewController {
    private let context: AccountContext
    private let snapshots: [DonutgramMessageRevision]
    private let incoming: Bool

    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private let _ready = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self._ready
    }

    private var controllerNode: DonutgramEditHistoryControllerNode {
        return self.displayNode as! DonutgramEditHistoryControllerNode
    }

    init(context: AccountContext, snapshots: [DonutgramMessageRevision], incoming: Bool) {
        self.context = context
        self.snapshots = snapshots
        self.incoming = incoming

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData, style: .glass))

        self._hasGlassStyle = true
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.title = "История правок"

        self.scrollToTop = { [weak self] in
            guard let self, self.isNodeLoaded else {
                return
            }
            self.controllerNode.scrollToFirstRevision()
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self, self.presentationData != presentationData else {
                return
            }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData, style: .glass), transition: .immediate)
            if self.isNodeLoaded {
                self.controllerNode.updatePresentationData(presentationData)
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = DonutgramEditHistoryControllerNode(context: self.context, presentationData: self.presentationData, snapshots: self.snapshots, incoming: self.incoming)
        self.displayNodeDidLoad()

        self._ready.set(self.controllerNode.ready)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

/// A transparent chat-style list over the screen's own full-screen wallpaper. Bubbles take their gradient or
/// wallpaper background from their position within the list, so the list and the wallpaper share one frame.
private final class DonutgramEditHistoryControllerNode: ViewControllerTracingNode {
    private let context: AccountContext
    private let snapshots: [DonutgramMessageRevision]
    private let incoming: Bool
    private var presentationData: PresentationData

    private let backgroundNode: WallpaperBackgroundNode
    private let listNode: ListView

    private var validLayout: (layout: ContainerViewLayout, navigationBarHeight: CGFloat)?
    private let listReady = ValuePromise<Bool>(false, ignoreRepeated: true)

    var ready: Signal<Bool, NoError> {
        // A wallpaper that still has to be fetched must not hold the push: the navigation controller ignores
        // all touches until the pushed screen is ready.
        let wallpaperReady = self.backgroundNode.isReady
        |> filter { $0 }
        |> take(1)
        |> timeout(0.5, queue: Queue.mainQueue(), alternate: .single(true))
        return combineLatest(wallpaperReady, self.listReady.get())
        |> map { backgroundReady, listReady -> Bool in
            return backgroundReady && listReady
        }
    }

    init(context: AccountContext, presentationData: PresentationData, snapshots: [DonutgramMessageRevision], incoming: Bool) {
        self.context = context
        self.presentationData = presentationData
        self.snapshots = snapshots
        self.incoming = incoming

        self.backgroundNode = createWallpaperBackgroundNode(context: context, forChatDisplay: true, useSharedAnimationPhase: true)
        self.backgroundNode.isUserInteractionEnabled = false
        self.backgroundNode.update(wallpaper: presentationData.chatWallpaper, animated: false)
        self.backgroundNode.updateBubbleTheme(bubbleTheme: presentationData.theme, bubbleCorners: presentationData.chatBubbleCorners)

        // Message item nodes are built for the bottom-up chat list, so this list is rotated the same way.
        self.listNode = ListViewImpl()
        self.listNode.transform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
        self.listNode.rotated = true

        super.init()

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.listNode)

        // Bubble shadows of custom themes live in the list's extracted-backgrounds container, as in a chat.
        self.listNode.enableExtractedBackgrounds = true
        self.listNode.accessibilityPageScrolledString = { [weak self] row, count in
            return self?.presentationData.strings.VoiceOver_ScrollStatus(row, count).string ?? ""
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        // The bubbles are read-only snapshots: touches on them go to the list itself, so it still scrolls,
        // but no tap, long-press or context menu gesture of a bubble starts.
        if let result, result.isDescendant(of: self.listNode.view) {
            return self.listNode.view
        }
        return result
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData

        self.backgroundNode.update(wallpaper: presentationData.chatWallpaper, animated: false)
        self.backgroundNode.updateBubbleTheme(bubbleTheme: presentationData.theme, bubbleCorners: presentationData.chatBubbleCorners)

        if self.validLayout != nil {
            self.updateItems(isInitial: false)
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let isFirstLayout = self.validLayout == nil
        self.validLayout = (layout, navigationBarHeight)

        let bounds = CGRect(origin: CGPoint(), size: layout.size)
        transition.updateFrame(node: self.backgroundNode, frame: bounds)
        self.backgroundNode.updateLayout(size: bounds.size, displayMode: .aspectFill, transition: transition)

        transition.updateBounds(node: self.listNode, bounds: bounds)
        transition.updatePosition(node: self.listNode, position: CGPoint(x: bounds.midX, y: bounds.midY))

        // The list is rotated, so its top inset is the bottom of the screen. The item nodes are rotated back
        // and read the side insets as they are on screen.
        let listInsets = UIEdgeInsets(top: layout.intrinsicInsets.bottom + 8.0, left: layout.safeInsets.left, bottom: navigationBarHeight + 8.0, right: layout.safeInsets.right)
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: listInsets, duration: duration, curve: curve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })

        if isFirstLayout {
            self.updateItems(isInitial: true)
        }
    }

    func scrollToFirstRevision() {
        guard self.validLayout != nil else {
            return
        }
        // The first revision is the last row of the rotated list, at the top of the screen.
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: self.snapshots.count - 1, position: .bottom(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Down), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }

    private func updateItems(isInitial: Bool) {
        let presentationData = self.presentationData

        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))
        let otherPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(2))
        let author: EngineRawPeer?
        if self.incoming {
            author = nil
        } else {
            author = TelegramUser(id: otherPeerId, accessHash: nil, firstName: "", lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        }

        // Newest first: index 0 is the bottom row of the rotated list, as in a chat.
        var items: [ListViewItem] = []
        for (index, snapshot) in self.snapshots.enumerated().reversed() {
            let messageId = EngineMessage.Id(peerId: self.incoming ? peerId : otherPeerId, namespace: 0, id: Int32(index + 1))
            let message = EngineRawMessage(stableId: UInt32(index + 1), stableVersion: 0, id: messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: snapshot.timestamp, flags: self.incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: author, text: snapshot.text, attributes: [], media: [], peers: EngineSimpleDictionary(), associatedMessages: EngineSimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            items.append(self.context.sharedContext.makeChatMessagePreviewItem(context: self.context, messages: [EngineMessage(message)], theme: presentationData.theme, strings: presentationData.strings, wallpaper: presentationData.chatWallpaper, fontSize: presentationData.chatFontSize, chatBubbleCorners: presentationData.chatBubbleCorners, dateTimeFormat: presentationData.dateTimeFormat, nameOrder: presentationData.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: self.backgroundNode, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: true, isStandalone: false, rank: nil, rankRole: nil, isGiftMessageComposerPreview: false, activateGiftMessageInput: nil))
        }

        if isInitial {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: items.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous, .LowLatency, .PreferSynchronousResourceLoading, .PreferSynchronousDrawing], scrollToItem: nil, updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { [weak self] _ in
                self?.listReady.set(true)
            })
        } else {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: items.enumerated().map { ListViewUpdateItem(index: $0.offset, previousIndex: $0.offset, item: $0.element, directionHint: nil) }, options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        }
    }
}
