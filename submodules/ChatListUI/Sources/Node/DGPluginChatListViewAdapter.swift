import Foundation
import TelegramCore
import LocalizedPeerData
import DGPluginModel
import DGPluginHost
import DGPluginViewAdapters

final class DGPluginChatListViewAdapter {
    private let manager: DGPluginManager
    private let lock = NSLock()
    private var visible = Set<EnginePeer.Id>()
    private var window = Set<EnginePeer.Id>()
    private var handles: [EnginePeer.Id: String] = [:]
    private var observer: UUID?
    var didChange: (() -> Void)?

    init(accountKey: String) {
        self.manager = DGPluginManager.shared(accountKey: accountKey)
        self.observer = self.manager.observe { [weak self] in self?.didChange?() }
    }

    deinit { if let observer = self.observer { self.manager.removeObserver(observer) } }

    private func eligible(_ entry: ChatListNodeEntry) -> ChatListNodeEntry.PeerEntryData? {
        guard case let .PeerEntry(row) = entry, case .chatList = row.index, row.promoInfo == nil, !row.isSideListAllThreadsItem, row.threadInfo == nil,
              row.peer.peerId.namespace != Namespaces.Peer.SecretChat, let peer = row.peer.chatMainPeer, !peer.isService else { return nil }
        return row
    }

    private func isPinned(_ row: ChatListNodeEntry.PeerEntryData) -> Bool {
        if case let .chatList(index) = row.index { return index.pinningIndex != nil }
        return true
    }

    func updateVisible(_ entries: [ChatListNodeEntry]) {
        let ids = Set(entries.prefix(40).compactMap { self.eligible($0)?.peer.peerId })
        self.lock.lock()
        let changed = self.visible != ids
        self.visible = ids
        self.lock.unlock()
        if changed { self.didChange?() }
    }

    func apply(_ entries: [ChatListNodeEntry]) -> [ChatListNodeEntry] {
        self.lock.lock()
        let visible = self.visible
        let retained = self.window
        self.lock.unlock()
        guard !visible.isEmpty else { return entries }
        let wanted = !retained.isDisjoint(with: visible) ? retained : visible
        var runs: [[Int]] = []
        var run: [Int] = []
        var pinned: [Int] = []
        for (index, entry) in entries.enumerated() {
            guard let row = self.eligible(entry) else { if !run.isEmpty { runs.append(run); run = [] }; continue }
            if self.isPinned(row) {
                if !run.isEmpty { runs.append(run); run = [] }
                if visible.contains(row.peer.peerId) { pinned.append(index) }
            } else if wanted.contains(row.peer.peerId), run.count < 40 {
                run.append(index)
            } else if !run.isEmpty { runs.append(run); run = [] }
        }
        if !run.isEmpty { runs.append(run) }
        guard let candidate = runs.max(by: { $0.count < $1.count }) else { return entries }
        let pinnedIndices = Array(pinned.reversed().prefix(12))
        let selected = Array(candidate.suffix(40 - pinnedIndices.count))
        guard let first = selected.first, let last = selected.last else { return entries }
        let indices = pinnedIndices + Array(selected.reversed())
        var rows: [DGPluginLocalChatRow] = []
        var original: [String: ChatListNodeEntry.PeerEntryData] = [:]
        self.lock.lock()
        let sourceIds = Set(entries.compactMap { self.eligible($0)?.peer.peerId })
        self.handles = self.handles.filter { sourceIds.contains($0.key) }
        if self.handles.count > 128 { self.handles = self.handles.filter { wanted.contains($0.key) || visible.contains($0.key) } }
        var retainedIds = Set<EnginePeer.Id>()
        for index in indices {
            guard let row = self.eligible(entries[index]), let peer = row.peer.chatMainPeer else { continue }
            let handle = self.handles[row.peer.peerId] ?? UUID().uuidString.lowercased()
            self.handles[row.peer.peerId] = handle
            retainedIds.insert(row.peer.peerId)
            let pinned = self.isPinned(row)
            let unread = max(Int(row.readState?.count ?? 0), row.readState?.markedUnread == true ? 1 : 0)
            rows.append(DGPluginLocalChatRow(handle: handle, title: peer.compactDisplayTitle, unread: unread, pinned: pinned))
            if !pinned { original[handle] = row }
        }
        self.window = retainedIds
        self.lock.unlock()
        let input = DGPluginLocalChatProjection.input(rows)
        let output = self.manager.transformedViewModel(slot: "chatList", input: input, update: { [weak self] in self?.didChange?() })
        guard output != input, let ordered = DGPluginLocalChatProjection.handles(rows: rows, output: output) else { return entries }
        let replacements = ordered.compactMap { original[$0] }.reversed()
        var result = entries
        let projected = replacements.map(ChatListNodeEntry.PeerEntry)
        result.replaceSubrange(first...last, with: projected)
        for index in first..<(first + projected.count) {
            if case var .PeerEntry(row) = result[index] { row.pluginLocalRank = index; result[index] = .PeerEntry(row) }
        }
        return result
    }
}
