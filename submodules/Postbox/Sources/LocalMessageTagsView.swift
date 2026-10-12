import Foundation

final class MutableLocalMessageTagsView: MutablePostboxView {
    private let tag: LocalMessageTags
    private let peerId: PeerId?
    fileprivate var messages: [MessageId: Message] = [:]
    
    init(postbox: PostboxImpl, tag: LocalMessageTags, peerId: PeerId?) {
        self.tag = tag
        self.peerId = peerId
        self.reload(postbox: postbox)
    }
    
    private func reload(postbox: PostboxImpl) {
        let ids: [MessageId]
        if let peerId = self.peerId {
            ids = postbox.localMessageHistoryTagsTable.get(tag: self.tag, peerId: peerId)
        } else {
            ids = postbox.localMessageHistoryTagsTable.get(tag: self.tag)
        }
        self.messages = [:]
        for id in ids {
            if let message = postbox.getMessage(id) {
                self.messages[message.id] = message
            }
        }
    }
    
    private func includes(_ id: MessageId, tag: LocalMessageTags) -> Bool {
        return tag == self.tag && (self.peerId == nil || id.peerId == self.peerId)
    }
    
    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool {
        var updated = false
        for operation in transaction.currentLocalTagsOperations {
            switch operation {
                case let .Insert(tag, id):
                    if self.includes(id, tag: tag) {
                        // The message can be gone already when it was tagged and then deleted
                        // in the same transaction.
                        if let message = postbox.getMessage(id) {
                            self.messages[id] = message
                            updated = true
                        }
                    }
                case let .Remove(tag, id):
                    if self.includes(id, tag: tag) {
                        if self.messages[id] != nil {
                            self.messages.removeValue(forKey: id)
                            updated = true
                        }
                    }
                case let .Update(tag, id):
                    if self.includes(id, tag: tag) {
                        if self.messages[id] != nil {
                            if let message = postbox.getMessage(id) {
                                self.messages[id] = message
                            } else {
                                self.messages.removeValue(forKey: id)
                            }
                            updated = true
                        }
                    }
            }
        }
        return updated
    }

    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool {
        return false
    }
    
    func immutableView() -> PostboxView {
        return LocalMessageTagsView(self)
    }
}

public final class LocalMessageTagsView: PostboxView {
    public var messages: [MessageId: Message] = [:]
    
    init(_ view: MutableLocalMessageTagsView) {
        self.messages = view.messages
    }
}
