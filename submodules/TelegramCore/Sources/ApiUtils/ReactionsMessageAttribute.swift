import Foundation
import DGSimpleSettings
import Postbox
internal import TelegramApi

extension ReactionsMessageAttribute {
    func withUpdatedResults(_ reactions: Api.MessageReactions) -> ReactionsMessageAttribute {
        switch reactions {
        case let .messageReactions(messageReactionsData):
            let (flags, results, recentReactions, topReactors) = (messageReactionsData.flags, messageReactionsData.results, messageReactionsData.recentReactions, messageReactionsData.topReactors)
            let min = (flags & (1 << 0)) != 0
            let canViewList = (flags & (1 << 2)) != 0
            let isTags = (flags & (1 << 3)) != 0
            var reactions = results.compactMap { result -> MessageReaction? in
                switch result {
                case let .reactionCount(reactionCountData):
                    let (_, chosenOrder, reaction, count) = (reactionCountData.flags, reactionCountData.chosenOrder, reactionCountData.reaction, reactionCountData.count)
                    if let reaction = MessageReaction.Reaction(apiReaction: reaction) {
                        return MessageReaction(value: reaction, count: count, chosenOrder: chosenOrder.flatMap(Int.init))
                    } else {
                        return nil
                    }
                }
            }
            let parsedRecentReactions: [ReactionsMessageAttribute.RecentPeer]
            if let recentReactions = recentReactions {
                parsedRecentReactions = recentReactions.compactMap { recentReaction -> ReactionsMessageAttribute.RecentPeer? in
                    switch recentReaction {
                    case let .messagePeerReaction(messagePeerReactionData):
                        let (flags, peerId, date, reaction) = (messagePeerReactionData.flags, messagePeerReactionData.peerId, messagePeerReactionData.date, messagePeerReactionData.reaction)
                        let isLarge = (flags & (1 << 0)) != 0
                        let isUnseen = (flags & (1 << 1)) != 0
                        let isMy = (flags & (1 << 2)) != 0
                        if let reaction = MessageReaction.Reaction(apiReaction: reaction) {
                            return ReactionsMessageAttribute.RecentPeer(value: reaction, isLarge: isLarge, isUnseen: isUnseen, isMy: isMy, peerId: peerId.peerId, timestamp: date)
                        } else {
                            return nil
                        }
                    }
                }
            } else {
                parsedRecentReactions = []
            }

            if min {
                var currentSelectedReactions: [MessageReaction.Reaction: Int] = [:]
                for reaction in self.reactions {
                    if let chosenOrder = reaction.chosenOrder {
                        currentSelectedReactions[reaction.value] = chosenOrder
                        break
                    }
                }
                if !currentSelectedReactions.isEmpty {
                    for i in 0 ..< reactions.count {
                        if let chosenOrder = currentSelectedReactions[reactions[i].value] {
                            reactions[i].chosenOrder = chosenOrder
                        }
                    }
                }
            }
            
            var topPeers: [ReactionsMessageAttribute.TopPeer] = []
            if let topReactors {
                for item in topReactors {
                    switch item {
                    case let .messageReactor(messageReactorData):
                        let (flags, peerId, count) = (messageReactorData.flags, messageReactorData.peerId, messageReactorData.count)
                        topPeers.append(ReactionsMessageAttribute.TopPeer(
                            peerId: peerId?.peerId,
                            count: count,
                            isTop: (flags & (1 << 0)) != 0,
                            isMy: (flags & (1 << 1)) != 0,
                            isAnonymous: (flags & (1 << 2)) != 0
                        ))
                    }
                }
            }

            return ReactionsMessageAttribute(canViewList: canViewList, isTags: isTags, reactions: reactions, recentPeers: parsedRecentReactions, topPeers: topPeers, removedReactions: self.removedReactions, removedPeers: self.removedPeers)
        }
    }
}

func donutgramRemovedReactions(previous: [MessageReaction], updated: [MessageReaction], retained: [MessageReaction], previousPeers: [ReactionsMessageAttribute.RecentPeer], updatedPeers: [ReactionsMessageAttribute.RecentPeer], retainedPeers: [ReactionsMessageAttribute.RecentPeer], enabled: Bool, hasPending: Bool) -> (reactions: [MessageReaction], peers: [ReactionsMessageAttribute.RecentPeer]) {
    if hasPending {
        return (retained, retainedPeers)
    }
    func otherCount(_ reactions: [MessageReaction], _ value: MessageReaction.Reaction) -> Int64 {
        guard let reaction = reactions.first(where: { $0.value == value }) else { return 0 }
        return max(0, Int64(reaction.count) - (reaction.isSelected ? 1 : 0))
    }
    func matches(_ lhs: ReactionsMessageAttribute.RecentPeer, _ rhs: ReactionsMessageAttribute.RecentPeer) -> Bool {
        return lhs.peerId == rhs.peerId && lhs.value == rhs.value
    }
    let previousPeers = previousPeers.filter { !$0.isMy && $0.value != .stars }
    let updatedPeers = updatedPeers.filter { !$0.isMy && $0.value != .stars }
    var peers = retainedPeers.filter { retained in
        return !updatedPeers.contains(where: { matches($0, retained) })
    }
    var values: [MessageReaction.Reaction] = []
    for reaction in retained + previous where reaction.value != .stars {
        if !values.contains(reaction.value) {
            values.append(reaction.value)
        }
    }
    var result: [MessageReaction] = []
    for value in values {
        let oldCount = otherCount(previous, value)
        let newCount = otherCount(updated, value)
        let oldPeers = previousPeers.filter { $0.value == value }
        let newPeers = updatedPeers.filter { $0.value == value }
        let lost = Int64(newPeers.count) >= newCount ? oldPeers.filter { old in !newPeers.contains(where: { matches($0, old) }) } : []
        let added = Int64(oldPeers.count) >= oldCount ? newPeers.filter { new in !oldPeers.contains(where: { matches($0, new) }) } : []
        if enabled {
            for var peer in lost where !peers.contains(where: { matches($0, peer) }) {
                peer.isUnseen = false
                peer.isLarge = false
                peers.append(peer)
            }
        }
        let savedCount = Int64(retained.first(where: { $0.value == value })?.count ?? 0)
        let savedPeersCount = Int64(retainedPeers.filter { $0.value == value }.count)
        let anonymousCount = max(0, savedCount - savedPeersCount)
        let anonymousLoss = enabled ? max(0, oldCount - newCount - Int64(lost.count) + Int64(added.count)) : 0
        let count = Int32(clamping: anonymousCount + anonymousLoss + Int64(peers.filter { $0.value == value }.count))
        if count > 0 {
            result.append(MessageReaction(value: value, count: count, chosenOrder: nil))
        }
    }
    return (result, peers)
}

func donutgramMergeRemovedReactions(messageId: MessageId, flags: MessageFlags, previous: [MessageAttribute], updated: inout [MessageAttribute]) {
    guard messageId.namespace == Namespaces.Message.Cloud, !flags.contains(.Incoming),
        let previousReactions = previous.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute,
        !previousReactions.isTags else {
        return
    }
    let index = updated.firstIndex(where: { $0 is ReactionsMessageAttribute })
    let current = index.flatMap { updated[$0] as? ReactionsMessageAttribute }
    if current?.isTags == true {
        return
    }
    let removed: (reactions: [MessageReaction], peers: [ReactionsMessageAttribute.RecentPeer])
    if let current {
        let hasPending = previous.contains(where: { $0 is PendingReactionsMessageAttribute }) || updated.contains(where: { $0 is PendingReactionsMessageAttribute })
        func otherPeers(_ attribute: ReactionsMessageAttribute) -> [ReactionsMessageAttribute.RecentPeer] {
            if messageId.peerId.namespace != Namespaces.Peer.CloudUser {
                return attribute.recentPeers
            }
            return attribute.reactions.filter { $0.value != .stars && $0.count > ($0.isSelected ? 1 : 0) }.map {
                ReactionsMessageAttribute.RecentPeer(value: $0.value, isLarge: false, isUnseen: false, isMy: false, peerId: messageId.peerId, timestamp: nil)
            }
        }
        removed = donutgramRemovedReactions(previous: previousReactions.reactions, updated: current.reactions, retained: previousReactions.removedReactions, previousPeers: otherPeers(previousReactions), updatedPeers: otherPeers(current), retainedPeers: previousReactions.removedPeers, enabled: DGSimpleSettings.shared.showRemovedReactions, hasPending: hasPending)
    } else {
        removed = (previousReactions.removedReactions, previousReactions.removedPeers)
    }
    if current == nil && removed.reactions.isEmpty {
        return
    }
    let attribute = ReactionsMessageAttribute(canViewList: current?.canViewList ?? false, isTags: false, reactions: current?.reactions ?? [], recentPeers: current?.recentPeers ?? [], topPeers: current?.topPeers ?? [], removedReactions: removed.reactions, removedPeers: removed.peers)
    if let index {
        updated[index] = attribute
    } else {
        updated.append(attribute)
    }
}

public func donutgramVisibleMessageReactions(attributes: [MessageAttribute], isTags: Bool) -> ReactionsMessageAttribute? {
    let current = mergedMessageReactions(attributes: attributes, isTags: isTags)
    var reactions = current?.reactions ?? []
    if DGSimpleSettings.shared.showRemovedReactions && !isTags,
        let stored = attributes.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute, !stored.isTags {
        for var reaction in stored.removedReactions where reaction.count > 0 && reaction.value != .stars {
            reaction.isRemoved = true
            reaction.chosenOrder = nil
            reactions.append(reaction)
        }
    }
    let hidePaid = DGSimpleSettings.shared.hidePaidReactions
    if hidePaid {
        reactions.removeAll(where: { $0.value == .stars })
    }
    guard current != nil || !reactions.isEmpty else { return nil }
    return ReactionsMessageAttribute(
        canViewList: current?.canViewList ?? false,
        isTags: current?.isTags ?? isTags,
        reactions: reactions,
        recentPeers: (current?.recentPeers ?? []).filter { !hidePaid || $0.value != .stars },
        topPeers: hidePaid ? [] : (current?.topPeers ?? [])
    )
}

public func mergedMessageReactionsAndPeers(accountPeerId: EnginePeer.Id, accountPeer: EnginePeer?, message: Message) -> (reactions: [MessageReaction], peers: [(MessageReaction.Reaction, EnginePeer)]) {
    guard let attribute = donutgramVisibleMessageReactions(attributes: message.attributes, isTags: message.areReactionsTags(accountPeerId: accountPeerId)) else {
        return ([], [])
    }
    
    var recentPeers: [(MessageReaction.Reaction, EnginePeer)] = []
    
    if message.id.peerId.namespace == Namespaces.Peer.CloudUser {
        for reaction in attribute.reactions where !reaction.isRemoved {
            var selfCount: Int32 = 0
            if reaction.isSelected {
                selfCount += 1
                if let accountPeer = accountPeer {
                    recentPeers.append((reaction.value, accountPeer))
                }
            }
            if reaction.count >= selfCount + 1 {
                if let peer = message.peers[message.id.peerId] {
                    recentPeers.append((reaction.value, EnginePeer(peer)))
                }
            }
        }
    } else {
        recentPeers = attribute.recentPeers.compactMap { recentPeer -> (MessageReaction.Reaction, EnginePeer)? in
            if let peer = message.peers[recentPeer.peerId] {
                return (recentPeer.value, EnginePeer(peer))
            } else {
                return nil
            }
        }
        if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info {
            recentPeers.removeAll()
        }
    }
    
    let reactions = attribute.reactions
    
    return (reactions, recentPeers)
}

private func mergeReactions(reactions: [MessageReaction], recentPeers: [ReactionsMessageAttribute.RecentPeer], pending: [PendingReactionsMessageAttribute.PendingReaction], accountPeerId: PeerId) -> ([MessageReaction], [ReactionsMessageAttribute.RecentPeer]) {
    var result = reactions
    var recentPeers = recentPeers
    
    var pendingIndex: Int = Int(Int32.max - 100)
    for pendingReaction in pending {
        if let index = result.firstIndex(where: { $0.value == pendingReaction.value }) {
            var merged = result[index]
            if merged.chosenOrder == nil {
                merged.chosenOrder = pendingIndex
                pendingIndex += 1
                merged.count += 1
            }
            result[index] = merged
        } else {
            result.append(MessageReaction(value: pendingReaction.value, count: 1, chosenOrder: pendingIndex))
            pendingIndex += 1
        }
        
        let pendingReactionSendAsPeerId = pendingReaction.sendAsPeerId ?? accountPeerId
        
        if let index = recentPeers.firstIndex(where: {
            $0.value == pendingReaction.value && ($0.peerId == pendingReactionSendAsPeerId || $0.isMy)
        }) {
            recentPeers.remove(at: index)
        }
        recentPeers.append(ReactionsMessageAttribute.RecentPeer(value: pendingReaction.value, isLarge: false, isUnseen: false, isMy: true, peerId: pendingReactionSendAsPeerId, timestamp: Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)))
    }
    
    for i in (0 ..< result.count).reversed() {
        if result[i].chosenOrder != nil {
            if !pending.contains(where: { $0.value == result[i].value }), result[i].value != .stars {
                if let index = recentPeers.firstIndex(where: { $0.value == result[i].value && ($0.peerId == accountPeerId || $0.isMy) }) {
                    recentPeers.remove(at: index)
                }
                
                if result[i].count <= 1 {
                    result.remove(at: i)
                } else {
                    result[i].count -= 1
                    result[i].chosenOrder = nil
                }
            }
        }
    }
    
    if recentPeers.count > 3 {
        recentPeers.removeFirst(recentPeers.count - 3)
    }
    
    return (result, recentPeers)
}

public func mergedMessageReactions(attributes: [MessageAttribute], isTags: Bool) -> ReactionsMessageAttribute? {
    var current: ReactionsMessageAttribute?
    var pending: PendingReactionsMessageAttribute?
    var pendingStars: PendingStarsReactionsMessageAttribute?
    for attribute in attributes {
        if let attribute = attribute as? ReactionsMessageAttribute {
            current = attribute
        } else if let attribute = attribute as? PendingReactionsMessageAttribute {
            pending = attribute
        } else if let attribute = attribute as? PendingStarsReactionsMessageAttribute {
            pendingStars = attribute
        }
    }
    
    let result: ReactionsMessageAttribute?
    if let pending = pending, let accountPeerId = pending.accountPeerId {
        var reactions = current?.reactions ?? []
        var recentPeers = current?.recentPeers ?? []
        
        let (updatedReactions, updatedRecentPeers) = mergeReactions(reactions: reactions, recentPeers: recentPeers, pending: pending.reactions, accountPeerId: accountPeerId)
        reactions = updatedReactions
        recentPeers = updatedRecentPeers
        
        if !reactions.isEmpty {
            result = ReactionsMessageAttribute(canViewList: current?.canViewList ?? false, isTags: current?.isTags ?? isTags, reactions: reactions, recentPeers: recentPeers, topPeers: current?.topPeers ?? [])
        } else {
            result = nil
        }
    } else if let current {
        result = current
    } else {
        result = nil
    }
    
    if let pendingStars {
        if let result {
            var reactions = result.reactions
            var updatedCount: Int32 = pendingStars.count
            if let index = reactions.firstIndex(where: { $0.value == .stars }) {
                updatedCount += reactions[index].count
                reactions.remove(at: index)
            }
            var topPeers = result.topPeers
            if let index = topPeers.firstIndex(where: { $0.isMy }) {
                topPeers[index].count += pendingStars.count
            } else {
                let isAnonymous: Bool
                let topPeerId: PeerId?
                switch pendingStars.privacy {
                case .anonymous:
                    isAnonymous = true
                    topPeerId = pendingStars.accountPeerId
                case .default:
                    isAnonymous = false
                    topPeerId = pendingStars.accountPeerId
                case let .peer(peerId):
                    isAnonymous = false
                    topPeerId = peerId
                }
                
                topPeers.append(ReactionsMessageAttribute.TopPeer(peerId: topPeerId, count: pendingStars.count, isTop: false, isMy: true, isAnonymous: isAnonymous))
            }
            reactions.insert(MessageReaction(value: .stars, count: updatedCount, chosenOrder: -1), at: 0)
            return ReactionsMessageAttribute(canViewList: current?.canViewList ?? false, isTags: current?.isTags ?? isTags, reactions: reactions, recentPeers: result.recentPeers, topPeers: topPeers)
        } else {
            let isAnonymous: Bool
            let topPeerId: PeerId?
            switch pendingStars.privacy {
            case .anonymous:
                isAnonymous = true
                topPeerId = pendingStars.accountPeerId
            case .default:
                isAnonymous = false
                topPeerId = pendingStars.accountPeerId
            case let .peer(peerId):
                isAnonymous = false
                topPeerId = peerId
            }
            
            return ReactionsMessageAttribute(canViewList: current?.canViewList ?? false, isTags: current?.isTags ?? isTags, reactions: [MessageReaction(value: .stars, count: pendingStars.count, chosenOrder: -1)], recentPeers: [], topPeers: [ReactionsMessageAttribute.TopPeer(peerId: topPeerId, count: pendingStars.count, isTop: false, isMy: true, isAnonymous: isAnonymous)])
        }
    } else {
        return result
    }
}

extension ReactionsMessageAttribute {
    convenience init(apiReactions: Api.MessageReactions) {
        switch apiReactions {
        case let .messageReactions(messageReactionsData):
            let (flags, results, recentReactions, topReactors) = (messageReactionsData.flags, messageReactionsData.results, messageReactionsData.recentReactions, messageReactionsData.topReactors)
            let canViewList = (flags & (1 << 2)) != 0
            let isTags = (flags & (1 << 3)) != 0
            let parsedRecentReactions: [ReactionsMessageAttribute.RecentPeer]
            if let recentReactions = recentReactions {
                parsedRecentReactions = recentReactions.compactMap { recentReaction -> ReactionsMessageAttribute.RecentPeer? in
                    switch recentReaction {
                    case let .messagePeerReaction(messagePeerReactionData):
                        let (flags, peerId, date, reaction) = (messagePeerReactionData.flags, messagePeerReactionData.peerId, messagePeerReactionData.date, messagePeerReactionData.reaction)
                        let isLarge = (flags & (1 << 0)) != 0
                        let isUnseen = (flags & (1 << 1)) != 0
                        let isMy = (flags & (1 << 2)) != 0
                        if let reaction = MessageReaction.Reaction(apiReaction: reaction) {
                            return ReactionsMessageAttribute.RecentPeer(value: reaction, isLarge: isLarge, isUnseen: isUnseen, isMy: isMy, peerId: peerId.peerId, timestamp: date)
                        } else {
                            return nil
                        }
                    }
                }
            } else {
                parsedRecentReactions = []
            }

            var topPeers: [ReactionsMessageAttribute.TopPeer] = []
            if let topReactors {
                for item in topReactors {
                    switch item {
                    case let .messageReactor(messageReactorData):
                        let (flags, peerId, count) = (messageReactorData.flags, messageReactorData.peerId, messageReactorData.count)
                        topPeers.append(ReactionsMessageAttribute.TopPeer(
                            peerId: peerId?.peerId,
                            count: count,
                            isTop: (flags & (1 << 0)) != 0,
                            isMy: (flags & (1 << 1)) != 0,
                            isAnonymous: (flags & (1 << 2)) != 0
                        ))
                    }
                }
            }

            self.init(
                canViewList: canViewList,
                isTags: isTags,
                reactions: results.compactMap { result -> MessageReaction? in
                    switch result {
                    case let .reactionCount(reactionCountData):
                        let (_, chosenOrder, reaction, count) = (reactionCountData.flags, reactionCountData.chosenOrder, reactionCountData.reaction, reactionCountData.count)
                        if let reaction = MessageReaction.Reaction(apiReaction: reaction) {
                            return MessageReaction(value: reaction, count: count, chosenOrder: chosenOrder.flatMap(Int.init))
                        } else {
                            return nil
                        }
                    }
                },
                recentPeers: parsedRecentReactions,
                topPeers: topPeers
            )
        }
    }
}
