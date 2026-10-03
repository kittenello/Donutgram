import Foundation
import DGSimpleSettings
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import WallpaperBackgroundNode
import Postbox

struct ChatPreviewMessageItem: Equatable {
    static func == (lhs: ChatPreviewMessageItem, rhs: ChatPreviewMessageItem) -> Bool {
        if lhs.outgoing != rhs.outgoing {
            return false
        }
        if let lhsReply = lhs.reply, let rhsReply = rhs.reply, lhsReply.0 != rhsReply.0 || lhsReply.1 != rhsReply.1 {
            return false
        } else if (lhs.reply == nil) != (rhs.reply == nil) {
            return false
        }
        if lhs.text != rhs.text {
            return false
        }
        if lhs.timestamp != rhs.timestamp || lhs.edited != rhs.edited {
            return false
        }
        if lhs.nameColor != rhs.nameColor {
            return false
        }
        if lhs.backgroundEmojiId != rhs.backgroundEmojiId {
            return false
        }
        if lhs.sticker != rhs.sticker || lhs.replySticker != rhs.replySticker {
            return false
        }
        return true
    }
    
    let outgoing: Bool
    let reply: (String, String)?
    let text: String
    let timestamp: Int32
    let edited: Bool
    let nameColor: PeerColor
    let backgroundEmojiId: Int64?
    let sticker: TelegramMediaFile?
    let replySticker: TelegramMediaFile?

    init(outgoing: Bool, reply: (String, String)?, text: String, timestamp: Int32 = 66000, edited: Bool = false, nameColor: PeerColor, backgroundEmojiId: Int64?, sticker: TelegramMediaFile? = nil, replySticker: TelegramMediaFile? = nil) {
        self.outgoing = outgoing
        self.reply = reply
        self.text = text
        self.timestamp = timestamp
        self.edited = edited
        self.nameColor = nameColor
        self.backgroundEmojiId = backgroundEmojiId
        self.sticker = sticker
        self.replySticker = replySticker
    }
}

class ThemeSettingsChatPreviewItem: ListViewItem, ItemListItem {
    let context: AccountContext
    let systemStyle: ItemListSystemStyle
    let theme: PresentationTheme
    let componentTheme: PresentationTheme
    let strings: PresentationStrings
    let sectionId: ItemListSectionId
    let fontSize: PresentationFontSize
    let chatBubbleCorners: PresentationChatBubbleCorners
    let wallpaper: TelegramWallpaper
    let dateTimeFormat: PresentationDateTimeFormat
    let nameDisplayOrder: PresentationPersonNameOrder
    let messageItems: [ChatPreviewMessageItem]
    
    init(context: AccountContext, systemStyle: ItemListSystemStyle = .legacy, theme: PresentationTheme, componentTheme: PresentationTheme, strings: PresentationStrings, sectionId: ItemListSectionId, fontSize: PresentationFontSize, chatBubbleCorners: PresentationChatBubbleCorners, wallpaper: TelegramWallpaper, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, messageItems: [ChatPreviewMessageItem]) {
        self.context = context
        self.systemStyle = systemStyle
        self.theme = theme
        self.componentTheme = componentTheme
        self.strings = strings
        self.sectionId = sectionId
        self.fontSize = fontSize
        self.chatBubbleCorners = chatBubbleCorners
        self.wallpaper = wallpaper
        self.dateTimeFormat = dateTimeFormat
        self.nameDisplayOrder = nameDisplayOrder
        self.messageItems = messageItems
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        // Bubble previews create views and synchronously consume main-queue
        // completion callbacks, including when ListView recycles an offscreen row.
        Queue.mainQueue().async {
            let node = ThemeSettingsChatPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ThemeSettingsChatPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                completion(layout, { _ in
                    apply()
                })
            }
        }
    }
}

public func donutgramMessagePreviewItem(context: AccountContext, sectionId: ItemListSectionId) -> ListViewItem {
    let current = context.sharedContext.currentPresentationData.with { $0 }
    // The bubbles apply the Donutgram tail/seconds/reply settings themselves, so keep the real corners (hasTails = false
    // would also hide the time) and a non-blue reply author, which stays distinguishable from the accent when colors are off.
    return ThemeSettingsChatPreviewItem(
        context: context,
        systemStyle: .glass,
        theme: current.theme,
        componentTheme: current.theme,
        strings: current.strings,
        sectionId: sectionId,
        fontSize: current.chatFontSize,
        chatBubbleCorners: current.chatBubbleCorners,
        wallpaper: current.chatWallpaper,
        dateTimeFormat: current.dateTimeFormat,
        nameDisplayOrder: current.nameDisplayOrder,
        messageItems: [
            ChatPreviewMessageItem(outgoing: false, reply: ("Donutgram", dgLocalized("Настройки сообщений", languageCode: current.strings.primaryComponent.languageCode)), text: dgLocalized("Так будет выглядеть входящее сообщение", languageCode: current.strings.primaryComponent.languageCode), timestamp: 66000, edited: false, nameColor: .preset(.red), backgroundEmojiId: nil),
            ChatPreviewMessageItem(outgoing: true, reply: nil, text: dgLocalized("И исходящее сообщение", languageCode: current.strings.primaryComponent.languageCode), timestamp: 66000, edited: true, nameColor: .preset(.blue), backgroundEmojiId: nil)
        ]
    )
}

public func donutgramStickerPreviewItem(context: AccountContext, sectionId: ItemListSectionId, sticker: TelegramMediaFile?) -> ListViewItem {
    let current = context.sharedContext.currentPresentationData.with { $0 }
    return ThemeSettingsChatPreviewItem(
        context: context,
        systemStyle: .glass,
        theme: current.theme,
        componentTheme: current.theme,
        strings: current.strings,
        sectionId: sectionId,
        fontSize: current.chatFontSize,
        chatBubbleCorners: current.chatBubbleCorners,
        wallpaper: current.chatWallpaper,
        dateTimeFormat: current.dateTimeFormat,
        nameDisplayOrder: current.nameDisplayOrder,
        messageItems: [
            ChatPreviewMessageItem(outgoing: false, reply: nil, text: dgLocalized("Вау!", languageCode: current.strings.primaryComponent.languageCode), nameColor: .preset(.blue), backgroundEmojiId: nil),
            ChatPreviewMessageItem(outgoing: true, reply: nil, text: sticker == nil ? current.strings.Channel_NotificationLoading : "", nameColor: .preset(.blue), backgroundEmojiId: nil, sticker: sticker),
            ChatPreviewMessageItem(outgoing: false, reply: ("Donutgram", dgLocalized("Стикер", languageCode: current.strings.primaryComponent.languageCode)), text: dgLocalized("Ого, какой милый!", languageCode: current.strings.primaryComponent.languageCode), nameColor: .preset(.blue), backgroundEmojiId: nil, replySticker: sticker)
        ]
    )
}

class ThemeSettingsChatPreviewItemNode: ListViewItemNode {
    private var backgroundNode: WallpaperBackgroundNode?
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let leftInsetNode: ASDisplayNode
    private let rightInsetNode: ASDisplayNode
    
    private let containerNode: ASDisplayNode
    private var messageNodes: [ListViewItemNode]?
    
    private var item: ThemeSettingsChatPreviewItem?
    private var finalImage = true
    
    private let disposable = MetaDisposable()

    override var visibility: ListViewItemNodeVisibility {
        didSet {
            self.updateMessageVisibility()
        }
    }

    private func updateMessageVisibility() {
        for node in self.messageNodes ?? [] {
            switch self.visibility {
            case .none:
                node.visibility = .none
            case let .visible(_, rect):
                // The container and message nodes are rotated: convert the visible rect into each child's coordinates.
                let visibleRect = self.convert(rect, to: node).intersection(node.bounds)
                if visibleRect.isNull || visibleRect.isEmpty {
                    node.visibility = .none
                } else {
                    node.visibility = .visible(visibleRect.height / max(1.0, node.bounds.height), visibleRect)
                }
            }
        }
    }
    
    init() {
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.maskNode = ASImageNode()
        self.leftInsetNode = ASDisplayNode()
        self.leftInsetNode.isLayerBacked = true
        self.rightInsetNode = ASDisplayNode()
        self.rightInsetNode.isLayerBacked = true
        
        self.containerNode = ASDisplayNode()
        self.containerNode.subnodeTransform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
        
        super.init(layerBacked: false)
        
        self.clipsToBounds = true
        
        self.addSubnode(self.containerNode)
        self.addSubnode(self.leftInsetNode)
        self.addSubnode(self.rightInsetNode)
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    func asyncLayout() -> (_ item: ThemeSettingsChatPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentNodes = self.messageNodes
        let currentMessages = self.item?.messageItems

        var currentBackgroundNode = self.backgroundNode
        
        return { item, params, neighbors in
            if currentBackgroundNode == nil {
                currentBackgroundNode = createWallpaperBackgroundNode(context: item.context, forChatDisplay: false)
            }
            currentBackgroundNode?.update(wallpaper: item.wallpaper, animated: false)
            currentBackgroundNode?.updateBubbleTheme(bubbleTheme: item.componentTheme, bubbleCorners: item.chatBubbleCorners)

            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            
            let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))
            let otherPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(2))
            var items: [ListViewItem] = []
            for (messageIndex, messageItem) in item.messageItems.reversed().enumerated() {
                var peers = EngineSimpleDictionary<EnginePeer.Id, EngineRawPeer>()
                var messages = EngineSimpleDictionary<EngineMessage.Id, EngineRawMessage>()
                
                let replyMessageId = EngineMessage.Id(peerId: peerId, namespace: 0, id: Int32(100 + messageIndex))
                if let (author, text) = messageItem.reply {
                    peers[peerId] = TelegramUser(id: peerId, accessHash: nil, firstName: author, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: messageItem.nameColor, backgroundEmojiId: messageItem.backgroundEmojiId, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
                    messages[replyMessageId] = EngineRawMessage(stableId: UInt32(100 + messageIndex), stableVersion: 0, id: replyMessageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 66000, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peers[peerId], text: text, attributes: [], media: messageItem.replySticker.map { [$0 as Media] } ?? [], peers: peers, associatedMessages: EngineSimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
                }
                
                var attributes: [MessageAttribute] = []
                if messageItem.reply != nil {
                    attributes.append(ReplyMessageAttribute(messageId: replyMessageId, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil))
                }
                if messageItem.edited {
                    attributes.append(EditedMessageAttribute(date: messageItem.timestamp, isHidden: false))
                }
                let message = EngineRawMessage(stableId: UInt32(messageIndex + 1), stableVersion: 0, id: EngineMessage.Id(peerId: messageItem.outgoing ? otherPeerId : peerId, namespace: 0, id: Int32(messageIndex + 1)), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: messageItem.timestamp, flags: messageItem.outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: messageItem.outgoing ? TelegramUser(id: otherPeerId, accessHash: nil, firstName: "", lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil) : nil, text: messageItem.text, attributes: attributes, media: messageItem.sticker.map { [$0 as Media] } ?? [], peers: peers, associatedMessages: messages, associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
                items.append(item.context.sharedContext.makeChatMessagePreviewItem(context: item.context, messages: [message], theme: item.componentTheme, strings: item.strings, wallpaper: item.wallpaper, fontSize: item.fontSize, chatBubbleCorners: item.chatBubbleCorners, dateTimeFormat: item.dateTimeFormat, nameOrder: item.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: currentBackgroundNode, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: true, isStandalone: false, rank: nil, rankRole: nil))
            }
            
            var nodes: [ListViewItemNode] = []
            if let messageNodes = currentNodes, currentMessages == item.messageItems, messageNodes.count == items.count {
                nodes = messageNodes
                for i in 0 ..< items.count {
                    let itemNode = messageNodes[i]
                    items[i].updateNode(async: { $0() }, node: {
                        return itemNode
                    }, params: params, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], animation: .None, completion: { (layout, apply) in
                        let nodeFrame = CGRect(origin: itemNode.frame.origin, size: CGSize(width: layout.size.width, height: layout.size.height))
                        
                        itemNode.contentSize = layout.contentSize
                        itemNode.insets = layout.insets
                        itemNode.frame = nodeFrame
                        itemNode.isUserInteractionEnabled = false
                        
                        apply(ListViewItemApply(isOnScreen: true))
                    })
                }
            } else {
                var messageNodes: [ListViewItemNode] = []
                for i in 0 ..< items.count {
                    var itemNode: ListViewItemNode?
                    items[i].nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: false, previousItem: i == 0 ? nil : items[i - 1], nextItem: i == (items.count - 1) ? nil : items[i + 1], completion: { node, apply in
                        itemNode = node
                        apply().1(ListViewItemApply(isOnScreen: true))
                    })
                    itemNode!.isUserInteractionEnabled = false
                    messageNodes.append(itemNode!)
                }
                nodes = messageNodes
            }
            
            var contentSize = CGSize(width: params.width, height: 4.0 + 4.0)
            for node in nodes {
                contentSize.height += node.frame.size.height
            }
            insets = itemListNeighborsGroupedInsets(neighbors, params)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    
                    strongSelf.containerNode.frame = CGRect(origin: CGPoint(), size: contentSize)
                    
                    for oldNode in strongSelf.messageNodes ?? [] where !nodes.contains(where: { $0 === oldNode }) {
                        oldNode.visibility = .none
                        oldNode.removeFromSupernode()
                    }
                    strongSelf.messageNodes = nodes
                    var topOffset: CGFloat = 4.0
                    for node in nodes {
                        if node.supernode == nil {
                            strongSelf.containerNode.addSubnode(node)
                        }
                        node.updateFrame(CGRect(origin: CGPoint(x: 0.0, y: topOffset), size: node.frame.size), within: layoutSize)
                        topOffset += node.frame.size.height
                    }
                    // New/relaid out nodes need visibility even if the list row's visibility has not changed.
                    strongSelf.updateMessageVisibility()

                    if let currentBackgroundNode = currentBackgroundNode, strongSelf.backgroundNode !== currentBackgroundNode {
                        strongSelf.backgroundNode = currentBackgroundNode
                        strongSelf.insertSubnode(currentBackgroundNode, at: 0)
                    }
                    
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }
                    
                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                        case .sameSection(false):
                            strongSelf.topStripeNode.isHidden = true
                        default:
                            hasTopCorners = true
                            strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = 0.0
                            bottomStripeOffset = -separatorHeight
                            strongSelf.bottomStripeNode.isHidden = false
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.componentTheme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil
                    
                    let backgroundFrame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    
                    let displayMode: WallpaperDisplayMode
                    if abs(params.availableHeight - params.width) < 100.0, params.availableHeight > 700.0 {
                        displayMode = .halfAspectFill
                    } else {
                        if backgroundFrame.width > backgroundFrame.height * 4.0 {
                            if params.availableHeight < 700.0 {
                                displayMode = .halfAspectFill
                            } else {
                                displayMode = .aspectFill
                            }
                        } else {
                            displayMode = .aspectFill
                        }
                    }
                    
                    if let backgroundNode = strongSelf.backgroundNode {
                        backgroundNode.frame = backgroundFrame.insetBy(dx: 0.0, dy: -100.0)
                        backgroundNode.updateLayout(size: backgroundNode.bounds.size, displayMode: displayMode, transition: .immediate)
                    }
                    strongSelf.maskNode.frame = backgroundFrame.insetBy(dx: params.leftInset, dy: 0.0)
                    // The wallpaper fills the preview, while grouped glass rows keep their horizontal margins.
                    strongSelf.leftInsetNode.isHidden = item.systemStyle != .glass
                    strongSelf.rightInsetNode.isHidden = item.systemStyle != .glass
                    strongSelf.leftInsetNode.backgroundColor = item.theme.list.blocksBackgroundColor
                    strongSelf.rightInsetNode.backgroundColor = item.theme.list.blocksBackgroundColor
                    strongSelf.leftInsetNode.frame = CGRect(x: 0.0, y: 0.0, width: params.leftInset, height: contentSize.height)
                    strongSelf.rightInsetNode.frame = CGRect(x: params.width - params.rightInset, y: 0.0, width: params.rightInset, height: contentSize.height)
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
