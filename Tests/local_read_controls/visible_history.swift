import Foundation

struct MessageId: Equatable { let id: Int32; let namespace: Int32 }
struct MessageIndex: Comparable {
    let id: MessageId
    init(_ value: Int32, namespace: Int32 = 0) { self.id = MessageId(id: value, namespace: namespace) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.id.id < rhs.id.id }
}
enum EngineMessage {
    typealias Id = MessageId
    typealias Index = MessageIndex
}
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }

struct ChatHistoryVisibleReadRow {}
func chatHistoryMaxVisibleReadIndex() {}
enum DonutgramShadowBan { static func readIndexPastHidden() {} }

struct FixtureMessage {
    let index: MessageIndex
    var id: MessageId { self.index.id }
}
struct FixtureEntry { let message: FixtureMessage }
struct FixtureHistoryView {
    let originalView: OriginalView
    struct OriginalView {
        var laterId: Int32?
        var holeLater = false
        let entries: [FixtureEntry]
    }
}
struct ChatHistoryTransactionOpaqueState { let historyView: FixtureHistoryView }
struct FixtureVisibleNode {
    struct Item { let content: [(FixtureMessage, Int)] }
    let item: Item?
    let frame: CGRect
}
final class FixtureListView {
    var opaqueTransactionState: Any?
    func itemNodeFrame(_ node: FixtureVisibleNode) -> CGRect? { node.frame }
}
final class HistoryNode {
    let listView = FixtureListView()
    var nodes: [FixtureVisibleNode] = []
    var insets = UIInsets()
    struct UIInsets { var top: CGFloat = 120 }
    var chatLocation = ChatLocation()
    struct ChatLocation { var threadId: Int64? }
    var readIndex: MessageIndex?
    var visibleIndices: [MessageIndex] = []
    var windowIndices: [MessageIndex] = []
    func forEachVisibleMessageItemNode(_ action: (FixtureVisibleNode) -> Void) {
        for node in self.nodes { action(node) }
    }
    func updateMaxVisibleReadIncomingMessageIndex(_ index: MessageIndex) { self.readIndex = index }
    func donutgramReadIndexPastHiddenMessages(_ index: MessageIndex) -> MessageIndex {
        DonutgramShadowBan.readIndexPastHidden(index, visibleIndices: self.visibleIndices, windowIndices: self.windowIndices)
    }
    func updateMaxVisibleReadIncomingMessageIndexFromVisibleItems() {}
    func readVisibleMessagesBeforeLeaving() {}
}

func seed(_ node: HistoryNode, visible: [MessageIndex], loaded: [MessageIndex], frame: CGRect, hasLater: Bool = false, holeLater: Bool = false) {
    node.visibleIndices = visible
    node.windowIndices = loaded
    node.nodes = [FixtureVisibleNode(item: .init(content: visible.map { (FixtureMessage(index: $0), 0) }), frame: frame)]
    let entries = loaded.map { FixtureEntry(message: FixtureMessage(index: $0)) }
    node.listView.opaqueTransactionState = ChatHistoryTransactionOpaqueState(historyView: FixtureHistoryView(originalView: .init(laterId: hasLater ? 99 : nil, holeLater: holeLater, entries: entries)))
    node.readIndex = nil
}

let node = HistoryNode()
let loaded = (1 ... 5).map { MessageIndex(Int32($0)) }
let visibleFrame = CGRect(x: 0, y: 120, width: 200, height: 50)
seed(node, visible: [MessageIndex(2)], loaded: loaded, frame: visibleFrame)
node.visibleIndices = [MessageIndex(1), MessageIndex(2), MessageIndex(5)]
node.updateMaxVisibleReadIncomingMessageIndexFromVisibleItems()
precondition(node.readIndex == MessageIndex(4), "scrolling reads hidden messages before the next visible message")
node.readIndex = nil
node.readVisibleMessagesBeforeLeaving()
precondition(node.readIndex == MessageIndex(4), "leaving mid-animation uses the same hidden-message boundary")
node.visibleIndices = [MessageIndex(1), MessageIndex(2)]
node.readVisibleMessagesBeforeLeaving()
precondition(node.readIndex == MessageIndex(5), "trailing hidden messages cannot leave an unread badge")

seed(node, visible: [MessageIndex(2)], loaded: [MessageIndex(2)], frame: CGRect(x: 0, y: 0, width: 200, height: 20))
node.readVisibleMessagesBeforeLeaving()
precondition(node.readIndex == nil, "a row fully under the input panel stays unread")
seed(node, visible: [MessageIndex(5)], loaded: loaded, frame: CGRect(x: 0, y: -80, width: 200, height: 250))
node.readVisibleMessagesBeforeLeaving()
precondition(node.readIndex == MessageIndex(5), "a tall newest row is read while partly visible")
for pending in [(true, false), (false, true)] {
    seed(node, visible: [MessageIndex(5)], loaded: loaded, frame: CGRect(x: 0, y: -80, width: 200, height: 250), hasLater: pending.0, holeLater: pending.1)
    node.readVisibleMessagesBeforeLeaving()
    precondition(node.readIndex == nil, "an incompletely loaded tall row cannot use the newest-message exception")
}
node.chatLocation.threadId = 10
seed(node, visible: [MessageIndex(5, namespace: 1)], loaded: loaded, frame: visibleFrame)
node.readVisibleMessagesBeforeLeaving()
precondition(node.readIndex == nil, "local messages in a thread cannot advance its cloud read marker")
print("visible history, leaving-chat and hidden-message boundary checks passed")
