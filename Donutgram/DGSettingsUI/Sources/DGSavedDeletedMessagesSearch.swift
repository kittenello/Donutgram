import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import MergeLists
import SearchBarNode
import GlassBackgroundComponent
import ComponentFlow
import ComponentDisplayAdapters
import AppBundle
import ActivityIndicator
import DGSimpleSettings

private let searchBarFont = Font.regular(17.0)

// How many found messages are shown; the newest come first, so a broader query hides the oldest.
private let searchResultLimit = 200

/// The search field that replaces the navigation bar while «Сохраненные удаленки» is searched.
/// The same glass field as the search of a group's members.
private final class DGSavedDeletedSearchNavigationContentNode: NavigationBarContentNode, ItemListControllerSearchNavigationContentNode {
    private struct Params: Equatable {
        let size: CGSize
        let leftInset: CGFloat
        let rightInset: CGFloat
    }

    private var theme: PresentationTheme
    private let strings: PresentationStrings

    private let cancel: () -> Void

    private let backgroundContainer: GlassBackgroundContainerView
    private let backgroundView: GlassBackgroundView
    private let iconView: UIImageView
    private var activityIndicator: ActivityIndicator?
    private let searchBar: SearchBarNode
    private let close: (background: GlassBackgroundView, icon: UIImageView)

    private var params: Params?

    private var queryUpdated: ((String) -> Void)?
    var activity: Bool = false {
        didSet {
            if self.activity != oldValue {
                if let params = self.params {
                    let _ = self.updateLayout(size: params.size, leftInset: params.leftInset, rightInset: params.rightInset, transition: .immediate)
                }
            }
        }
    }

    init(theme: PresentationTheme, strings: PresentationStrings, cancel: @escaping () -> Void, updateActivity: @escaping (@escaping (Bool) -> Void) -> Void) {
        self.theme = theme
        self.strings = strings

        self.cancel = cancel

        self.backgroundContainer = GlassBackgroundContainerView()
        self.backgroundView = GlassBackgroundView()
        self.backgroundContainer.contentView.addSubview(self.backgroundView)
        self.iconView = UIImageView()
        self.backgroundView.contentView.addSubview(self.iconView)

        self.close = (GlassBackgroundView(), UIImageView())
        self.close.background.contentView.addSubview(self.close.icon)

        self.searchBar = SearchBarNode(
            theme: SearchBarNodeTheme(
                background: .clear,
                separator: .clear,
                inputFill: .clear,
                primaryText: theme.chat.inputPanel.panelControlColor,
                placeholder: theme.chat.inputPanel.inputPlaceholderColor,
                inputIcon: theme.chat.inputPanel.inputControlColor,
                inputClear: theme.chat.inputPanel.panelControlColor,
                accent: theme.chat.inputPanel.panelControlAccentColor,
                keyboard: theme.rootController.keyboardColor
            ),
            presentationTheme: theme,
            strings: strings,
            fieldStyle: .inlineNavigation,
            forceSeparator: false,
            displayBackground: false,
            cancelText: nil
        )

        super.init()

        self.view.addSubview(self.backgroundContainer)
        self.backgroundView.contentView.addSubview(self.searchBar.view)

        self.backgroundContainer.contentView.addSubview(self.close.background)
        self.close.background.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onCloseTapGesture(_:))))

        self.searchBar.cancel = { [weak self] in
            self?.searchBar.deactivate(clear: false)
            self?.cancel()
        }

        self.searchBar.textUpdated = { [weak self] query, _ in
            self?.queryUpdated?(query)
        }

        updateActivity({ [weak self] value in
            self?.activity = value
        })

        self.updatePlaceholder()
    }

    @objc private func onCloseTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.searchBar.cancel?()
        }
    }

    func setQueryUpdated(_ f: @escaping (String) -> Void) {
        self.queryUpdated = f
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        if let params = self.params {
            let _ = self.updateLayout(size: params.size, leftInset: params.leftInset, rightInset: params.rightInset, transition: .immediate)
        }
        self.updatePlaceholder()
    }

    private func updatePlaceholder() {
        let placeholder = dgLocalized("Поиск по удаленкам", languageCode: self.strings.primaryComponent.languageCode)
        self.searchBar.placeholderString = NSAttributedString(string: placeholder, font: searchBarFont, textColor: self.theme.rootController.navigationSearchBar.inputPlaceholderTextColor)
    }

    override var nominalHeight: CGFloat {
        return 60.0
    }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        self.params = Params(size: size, leftInset: leftInset, rightInset: rightInset)

        let transition = ComponentTransition(transition)

        let backgroundFrame = CGRect(origin: CGPoint(x: leftInset + 16.0, y: 6.0), size: CGSize(width: size.width - 16.0 * 2.0 - leftInset - rightInset - 44.0 - 8.0, height: 44.0))
        let closeFrame = CGRect(origin: CGPoint(x: size.width - 16.0 - rightInset - 44.0, y: backgroundFrame.minY), size: CGSize(width: 44.0, height: 44.0))

        transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: CGPoint(), size: size))
        self.backgroundContainer.update(size: size, isDark: self.theme.overallDarkAppearance, transition: transition)

        transition.setFrame(view: self.backgroundView, frame: backgroundFrame)
        self.backgroundView.update(size: backgroundFrame.size, cornerRadius: backgroundFrame.height * 0.5, isDark: self.theme.overallDarkAppearance, tintColor: .init(kind: .panel), isInteractive: true, transition: transition)

        if self.iconView.image == nil {
            self.iconView.image = UIImage(bundleImageName: "Navigation/Search")?.withRenderingMode(.alwaysTemplate)
        }
        transition.setTintColor(view: self.iconView, color: self.theme.rootController.navigationSearchBar.inputIconColor)

        if let image = self.iconView.image {
            let iconFraction: CGFloat = 0.8
            let imageSize = CGSize(width: image.size.width * iconFraction, height: image.size.height * iconFraction)
            let iconFrame = CGRect(origin: CGPoint(x: 12.0, y: floor((backgroundFrame.height - imageSize.height) * 0.5)), size: imageSize)
            transition.setPosition(view: self.iconView, position: iconFrame.center)
            transition.setBounds(view: self.iconView, bounds: CGRect(origin: CGPoint(), size: iconFrame.size))
        }

        if self.activity {
            let activityIndicator: ActivityIndicator
            if let current = self.activityIndicator {
                activityIndicator = current
            } else {
                activityIndicator = ActivityIndicator(type: .custom(self.theme.chat.inputPanel.inputControlColor, 14.0, 14.0, false))
                self.activityIndicator = activityIndicator
                self.backgroundView.contentView.addSubview(activityIndicator.view)
            }
            let indicatorSize = activityIndicator.measure(CGSize(width: 32.0, height: 32.0))
            let indicatorFrame = CGRect(origin: CGPoint(x: 15.0, y: floorToScreenPixels((backgroundFrame.height - indicatorSize.height) * 0.5)), size: indicatorSize)
            transition.setPosition(view: activityIndicator.view, position: indicatorFrame.center)
            transition.setBounds(view: activityIndicator.view, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
        } else if let activityIndicator = self.activityIndicator {
            self.activityIndicator = nil
            activityIndicator.view.removeFromSuperview()
        }
        self.iconView.isHidden = self.activity

        let searchBarFrame = CGRect(origin: CGPoint(x: 36.0, y: 0.0), size: CGSize(width: backgroundFrame.width - 36.0 - 4.0, height: 44.0))
        transition.setFrame(view: self.searchBar.view, frame: searchBarFrame)
        self.searchBar.updateLayout(boundingSize: searchBarFrame.size, leftInset: 0.0, rightInset: 0.0, transition: transition.containedViewLayoutTransition)

        if self.close.icon.image == nil {
            self.close.icon.image = generateImage(CGSize(width: 40.0, height: 40.0), contextGenerator: { size, context in
                context.clear(CGRect(origin: CGPoint(), size: size))

                context.setLineWidth(2.0)
                context.setLineCap(.round)
                context.setStrokeColor(UIColor.white.cgColor)

                context.beginPath()
                context.move(to: CGPoint(x: 12.0, y: 12.0))
                context.addLine(to: CGPoint(x: size.width - 12.0, y: size.height - 12.0))
                context.move(to: CGPoint(x: size.width - 12.0, y: 12.0))
                context.addLine(to: CGPoint(x: 12.0, y: size.height - 12.0))
                context.strokePath()
            })?.withRenderingMode(.alwaysTemplate)
        }

        if let image = self.close.icon.image {
            self.close.icon.frame = image.size.centered(in: CGRect(origin: CGPoint(), size: closeFrame.size))
        }
        self.close.icon.tintColor = self.theme.chat.inputPanel.panelControlColor

        transition.setFrame(view: self.close.background, frame: closeFrame)
        self.close.background.update(size: closeFrame.size, cornerRadius: closeFrame.height * 0.5, isDark: self.theme.overallDarkAppearance, tintColor: .init(kind: .panel), isInteractive: true, transition: transition)

        return size
    }

    func activate() {
        self.searchBar.activate()
    }

    func deactivate() {
        self.searchBar.deactivate(clear: false)
    }
}

/// Search of «Сохраненные удаленки» by message text, across every chat that keeps saved deleted
/// messages. A found message opens in its chat at that message.
final class DGSavedDeletedSearchItem: ItemListControllerSearch {
    let context: AccountContext
    let cancel: () -> Void
    let openMessage: (EnginePeer, EngineMessage) -> Void
    let dismissInput: () -> Void

    private var updateActivity: ((Bool) -> Void)?
    private let activity = ValuePromise<Bool>(ignoreRepeated: false)
    private let activityDisposable = MetaDisposable()

    init(context: AccountContext, cancel: @escaping () -> Void, openMessage: @escaping (EnginePeer, EngineMessage) -> Void, dismissInput: @escaping () -> Void) {
        self.context = context
        self.cancel = cancel
        self.openMessage = openMessage
        self.dismissInput = dismissInput
        self.activityDisposable.set((self.activity.get()
        |> mapToSignal { value -> Signal<Bool, NoError> in
            if value {
                return .single(value) |> delay(0.2, queue: Queue.mainQueue())
            } else {
                return .single(value)
            }
        }).start(next: { [weak self] value in
            self?.updateActivity?(value)
        }))
    }

    deinit {
        self.activityDisposable.dispose()
    }

    func isEqual(to: ItemListControllerSearch) -> Bool {
        if let to = to as? DGSavedDeletedSearchItem {
            return self.context === to.context
        } else {
            return false
        }
    }

    func titleContentNode(current: (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)?) -> (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)? {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        if let current = current as? DGSavedDeletedSearchNavigationContentNode {
            current.updateTheme(presentationData.theme)
            return current
        } else {
            return DGSavedDeletedSearchNavigationContentNode(theme: presentationData.theme, strings: presentationData.strings, cancel: self.cancel, updateActivity: { [weak self] value in
                self?.updateActivity = value
            })
        }
    }

    func node(current: ItemListControllerSearchNode?, titleContentNode: (NavigationBarContentNode & ItemListControllerSearchNavigationContentNode)?) -> ItemListControllerSearchNode {
        if let current = current as? DGSavedDeletedSearchNode {
            return current
        }
        return DGSavedDeletedSearchNode(context: self.context, openMessage: self.openMessage, cancel: self.cancel, updateActivity: { [weak self] value in
            self?.activity.set(value)
        }, dismissInput: self.dismissInput)
    }
}

private struct DGSavedDeletedSearchEntry: Comparable, Identifiable {
    let index: Int
    let message: EngineMessage
    let peer: EnginePeer
    let text: String
    let date: String
    let theme: PresentationTheme

    var stableId: EngineMessage.Id {
        return self.message.id
    }

    static func ==(lhs: DGSavedDeletedSearchEntry, rhs: DGSavedDeletedSearchEntry) -> Bool {
        return lhs.index == rhs.index && lhs.message.id == rhs.message.id && lhs.message.stableVersion == rhs.message.stableVersion && lhs.peer == rhs.peer && lhs.text == rhs.text && lhs.date == rhs.date && lhs.theme === rhs.theme
    }

    static func <(lhs: DGSavedDeletedSearchEntry, rhs: DGSavedDeletedSearchEntry) -> Bool {
        return lhs.index < rhs.index
    }

    func item(context: AccountContext, presentationData: PresentationData, openMessage: @escaping (EnginePeer, EngineMessage) -> Void) -> ListViewItem {
        let peer = self.peer
        let message = self.message
        return ItemListPeerItem(presentationData: ItemListPresentationData(presentationData), systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: context, peer: peer, presence: nil, text: .text(self.text, .secondary), label: .text(self.date, .standard, nil, false), editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: 0, action: {
            openMessage(peer, message)
        }, setPeerIdWithRevealedOptions: { _, _ in
        }, removePeer: { _ in
        }, style: .plain)
    }
}

private struct DGSavedDeletedSearchTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let isSearching: Bool
    let isEmpty: Bool
    let query: String
}

/// One line of a found message: in a group the sender goes first, as in the chat list.
private func dgSavedDeletedSearchSnippet(message: EngineMessage, peer: EnginePeer, searchText: String) -> String {
    var text = message.text.isEmpty ? searchText : message.text
    text = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    var isGroup = false
    switch peer {
    case .legacyGroup:
        isGroup = true
    case let .channel(channel):
        if case .group = channel.info {
            isGroup = true
        }
    default:
        break
    }
    if isGroup, let author = message.author, author.id != peer.id {
        text = author.compactDisplayTitle + ": " + text
    }
    return text
}

private final class DGSavedDeletedSearchNode: ItemListControllerSearchNode {
    private let cancel: () -> Void

    private let dimNode: ASDisplayNode
    private let listNode: ListView
    private let emptyResultsTitleNode: ImmediateTextNode
    private let emptyResultsTextNode: ImmediateTextNode

    private var presentationData: PresentationData
    private var enqueuedTransitions: [DGSavedDeletedSearchTransition] = []
    private var validLayout: (ContainerViewLayout, CGFloat)?

    private let query = ValuePromise<String>("", ignoreRepeated: true)
    private var searchDisposable: Disposable?
    private var presentationDataDisposable: Disposable?

    init(context: AccountContext, openMessage: @escaping (EnginePeer, EngineMessage) -> Void, cancel: @escaping () -> Void, updateActivity: @escaping (Bool) -> Void, dismissInput: @escaping () -> Void) {
        self.cancel = cancel

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        self.dimNode = ASDisplayNode()
        self.dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        self.listNode = ListViewImpl()
        self.listNode.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.listNode.isHidden = true
        self.listNode.accessibilityPageScrolledString = { row, count in
            return presentationData.strings.VoiceOver_ScrollStatus(row, count).string
        }

        self.emptyResultsTitleNode = ImmediateTextNode()
        self.emptyResultsTitleNode.displaysAsynchronously = false
        self.emptyResultsTitleNode.attributedText = NSAttributedString(string: presentationData.strings.ChatList_Search_NoResults, font: Font.semibold(17.0), textColor: presentationData.theme.list.freeTextColor)
        self.emptyResultsTitleNode.textAlignment = .center
        self.emptyResultsTitleNode.isHidden = true

        self.emptyResultsTextNode = ImmediateTextNode()
        self.emptyResultsTextNode.displaysAsynchronously = false
        self.emptyResultsTextNode.maximumNumberOfLines = 0
        self.emptyResultsTextNode.textAlignment = .center
        self.emptyResultsTextNode.isHidden = true

        super.init()

        self.addSubnode(self.dimNode)
        self.addSubnode(self.listNode)
        self.addSubnode(self.emptyResultsTitleNode)
        self.addSubnode(self.emptyResultsTextNode)

        // Read once per search: typing filters the text in memory.
        let searchIndex = Promise<[DonutgramPreservedMessageSearchEntry]?>(nil)
        searchIndex.set(context.engine.messages.donutgramPreservedMessagesSearchIndex()
        |> map(Optional.init))

        // nil until a query with letters or digits is typed: the page then stays dimmed.
        let foundMessages: Signal<(String, [(EngineMessage, EnginePeer, String)]?), NoError> = combineLatest(self.query.get(), searchIndex.get())
        |> mapToSignal { query, index -> Signal<(String, [(EngineMessage, EnginePeer, String)]?), NoError> in
            if !query.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                return .single((query, nil))
            }
            updateActivity(true)
            guard let index else {
                // The index is still being read; this runs again once it is ready.
                return .never()
            }
            return Signal<[EngineMessage.Id], NoError> { subscriber in
                subscriber.putNext(donutgramPreservedMessageIds(matching: query, in: index, limit: searchResultLimit))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(Queue.concurrentDefaultQueue())
            |> mapToSignal { messageIds -> Signal<(String, [(EngineMessage, EnginePeer, String)]?), NoError> in
                let messageIdSet = Set(messageIds)
                let searchTexts = Dictionary(index.lazy.filter { messageIdSet.contains($0.id) }.map { ($0.id, $0.text) }, uniquingKeysWith: { lhs, _ in lhs })
                let peerIds = Set(messageIds.map(\.peerId))
                return context.engine.data.get(
                    TelegramEngine.EngineData.Item.Messages.Messages(ids: messageIdSet),
                    EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:)))
                )
                |> map { messages, peers -> (String, [(EngineMessage, EnginePeer, String)]?) in
                    var result: [(EngineMessage, EnginePeer, String)] = []
                    // A message deleted from this device since the search opened has no row.
                    for id in messageIds {
                        guard let message = messages[id], let peer = peers[id.peerId] ?? nil else {
                            continue
                        }
                        result.append((message, peer, searchTexts[id] ?? ""))
                    }
                    return (query, result)
                }
            }
        }

        let previousEntries = Atomic<[DGSavedDeletedSearchEntry]?>(value: nil)
        self.searchDisposable = (foundMessages
        |> deliverOnMainQueue).start(next: { [weak self] query, found in
            guard let self else {
                return
            }
            updateActivity(false)
            let presentationData = self.presentationData
            let entries: [DGSavedDeletedSearchEntry]? = found.map { found in
                return found.enumerated().map { index, item -> DGSavedDeletedSearchEntry in
                    let (message, peer, searchText) = item
                    let date = stringForMediumDate(timestamp: message.timestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
                    return DGSavedDeletedSearchEntry(index: index, message: message, peer: peer, text: dgSavedDeletedSearchSnippet(message: message, peer: peer, searchText: searchText), date: date, theme: presentationData.theme)
                }
            }
            let previous = previousEntries.swap(entries)
            let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: previous ?? [], rightList: entries ?? [])
            let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
            let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, openMessage: openMessage), directionHint: nil) }
            let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, openMessage: openMessage), directionHint: nil) }
            self.enqueueTransition(DGSavedDeletedSearchTransition(deletions: deletions, insertions: insertions, updates: updates, isSearching: entries != nil, isEmpty: entries?.isEmpty ?? false, query: query))
        })

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.listNode.backgroundColor = presentationData.theme.list.plainBackgroundColor
            }
        })

        self.listNode.beganInteractiveDragging = { _ in
            dismissInput()
        }
    }

    deinit {
        self.searchDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
    }

    override func didLoad() {
        super.didLoad()

        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapGesture(_:))))
    }

    @objc private func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.cancel()
        }
    }

    override func queryUpdated(_ query: String) {
        self.query.set(query)
    }

    private func enqueueTransition(_ transition: DGSavedDeletedSearchTransition) {
        self.enqueuedTransitions.append(transition)
        if self.validLayout != nil {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }

    private func dequeueTransition() {
        guard let transition = self.enqueuedTransitions.first else {
            return
        }
        self.enqueuedTransitions.remove(at: 0)

        var options = ListViewDeleteAndInsertOptions()
        options.insert(.PreferSynchronousDrawing)
        options.insert(.PreferSynchronousResourceLoading)

        self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
            guard let self else {
                return
            }
            self.listNode.isHidden = !transition.isSearching
            self.dimNode.isHidden = transition.isSearching

            self.emptyResultsTextNode.attributedText = NSAttributedString(string: self.presentationData.strings.ChatList_Search_NoResultsQueryDescription(transition.query).string, font: Font.regular(15.0), textColor: self.presentationData.theme.list.freeTextColor)
            let emptyResults = transition.isSearching && transition.isEmpty
            self.emptyResultsTitleNode.isHidden = !emptyResults
            self.emptyResultsTextNode.isHidden = !emptyResults

            if let (layout, navigationBarHeight) = self.validLayout {
                self.updateLayout(layout: layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        })
    }

    override func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }

    override func updateLayout(layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let hadValidLayout = self.validLayout != nil
        self.validLayout = (layout, navigationBarHeight)

        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)

        var insets = layout.insets(options: [.input])
        insets.top += navigationBarHeight
        insets.left += layout.safeInsets.left
        insets.right += layout.safeInsets.right

        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: 0.0, y: navigationBarHeight), size: CGSize(width: layout.size.width, height: max(0.0, layout.size.height - navigationBarHeight))))

        self.listNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, duration: duration, curve: curve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })

        let padding: CGFloat = 16.0
        let textWidth = layout.size.width - layout.safeInsets.left - layout.safeInsets.right - padding * 2.0
        let emptyTitleSize = self.emptyResultsTitleNode.updateLayout(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        let emptyTextSize = self.emptyResultsTextNode.updateLayout(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))

        let emptyTextSpacing: CGFloat = 8.0
        let emptyTotalHeight = emptyTitleSize.height + emptyTextSize.height + emptyTextSpacing
        let emptyTitleY = navigationBarHeight + floorToScreenPixels((layout.size.height - navigationBarHeight - max(insets.bottom, layout.intrinsicInsets.bottom) - emptyTotalHeight) / 2.0)

        transition.updateFrame(node: self.emptyResultsTitleNode, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left + padding + (textWidth - emptyTitleSize.width) / 2.0, y: emptyTitleY), size: emptyTitleSize))
        transition.updateFrame(node: self.emptyResultsTextNode, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left + padding + (textWidth - emptyTextSize.width) / 2.0, y: emptyTitleY + emptyTitleSize.height + emptyTextSpacing), size: emptyTextSize))

        if !hadValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }

    // The page never sets this node's own frame, so its bounds are empty: touches are passed to
    // the visible child directly, as the search of a group's members does.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !self.listNode.isHidden, let result = self.listNode.hitTest(self.view.convert(point, to: self.listNode.view), with: event) {
            return result
        }
        if !self.dimNode.isHidden, let result = self.dimNode.hitTest(self.view.convert(point, to: self.dimNode.view), with: event) {
            return result
        }
        return nil
    }
}
