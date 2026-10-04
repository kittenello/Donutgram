import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

/// Telegram user ids are positive decimal integers. Reject phone numbers,
/// usernames and ids outside Postbox's 56-bit peer-id representation.
public func donutgramUserIdFromSearchQuery(_ query: String) -> Int64? {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let id = Int64(value), id > 0, id <= 0x00ffffffffffffff else {
        return nil
    }
    return id
}

func donutgramSearchUserById(accountPeerId: PeerId, postbox: Postbox, network: Network, userId: Int64, scope: TelegramSearchPeersScope) -> Signal<FoundPeer?, NoError> {
    switch scope {
    case .everywhere, .privateChats, .bots:
        break
    default:
        return .single(nil)
    }
    let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(userId))
    return postbox.transaction { transaction -> TelegramUser? in
        return transaction.getPeer(peerId) as? TelegramUser
    }
    |> mapToSignal { cachedUser -> Signal<FoundPeer?, NoError> in
        if let user = cachedUser, donutgramCanOpenIdSearchUser(user, accountPeerId: accountPeerId) {
            if case .bots = scope, user.botInfo == nil {
                return .single(nil)
            }
            return .single(FoundPeer(peer: EnginePeer(user), subscribers: user.subscriberCount))
        }

        let inputUser: Api.InputUser
        if peerId == accountPeerId {
            inputUser = .inputUserSelf
        } else {
            // An id alone is not always resolvable. Ask the server once without
            // inventing a peer or access hash; unavailable users yield no result.
            inputUser = cachedUser.flatMap(apiInputUser) ?? .inputUser(.init(userId: userId, accessHash: 0))
        }
        return network.request(Api.functions.users.getUsers(id: [inputUser]), automaticFloodWait: false)
        |> map(Optional.init)
        |> `catch` { _ -> Signal<[Api.User]?, NoError> in
            return .single(nil)
        }
        |> timeout(4.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
        |> mapToSignal { users -> Signal<FoundPeer?, NoError> in
            guard let users else {
                return .single(nil)
            }
            return postbox.transaction { transaction -> FoundPeer? in
                let matchingUsers = users.filter { user in
                    guard case .user = user else { return false }
                    return user.peerId == peerId
                }
                guard !matchingUsers.isEmpty else {
                    return nil
                }
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: AccumulatedPeers(users: matchingUsers))
                guard let user = transaction.getPeer(peerId) as? TelegramUser,
                      donutgramCanOpenIdSearchUser(user, accountPeerId: accountPeerId) else {
                    return nil
                }
                if case .bots = scope, user.botInfo == nil {
                    return nil
                }
                return FoundPeer(peer: EnginePeer(user), subscribers: user.subscriberCount)
            }
        }
    }
}

func donutgramCanOpenIdSearchUser(_ user: TelegramUser, accountPeerId: PeerId) -> Bool {
    guard !user.isDeleted else {
        return false
    }
    if user.id == accountPeerId {
        return true
    }
    if let accessHash = user.accessHash, case .personal = accessHash {
        return true
    }
    return false
}

func donutgramAddingUserIdResult(_ user: FoundPeer?, to results: ([FoundPeer], [FoundPeer])) -> ([FoundPeer], [FoundPeer]) {
    guard let user else {
        return results
    }
    return ([user] + results.0.filter { $0.peer.id != user.peer.id }, results.1.filter { $0.peer.id != user.peer.id })
}
