import AccountContext
import TelegramCore
import SwiftSignalKit
import DGSimpleSettings

private func localVerificationPeer(context: AccountContext, username: String) -> Signal<EnginePeer?, NoError> {
    return context.engine.peers.resolvePeerByName(name: username, referrer: nil)
    |> filter { result in
        if case .result = result { return true }
        return false
    }
    |> take(1)
    |> map { result in
        if case let .result(peer) = result { return peer }
        return nil
    }
}

private func localVerificationData(context: AccountContext, peer: EnginePeer) -> Signal<EngineCachedPeerData?, NoError> {
    return context.engine.peers.fetchAndUpdateCachedPeerData(peerId: peer.id)
    |> mapToSignal { _ in
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.CachedData(id: peer.id))
    }
}

private func localVerificationDetails(context: AccountContext, peer: EnginePeer, expectedBotId: Int64?) -> Signal<DGLocalVerificationDetails?, NoError> {
    return localVerificationData(context: context, peer: peer)
    |> map { data in
        let verification = (data as? CachedUserData)?.verification ?? (data as? CachedChannelData)?.verification
        guard let verification, verification.iconFileId != 0,
              expectedBotId == nil || verification.botId.id._internalGetInt64Value() == expectedBotId else { return nil }
        return DGLocalVerificationDetails(iconFileId: verification.iconFileId, botId: verification.botId.id._internalGetInt64Value(), description: verification.description)
    }
}

private func localVerificationReferences(context: AccountContext, usernames: [String], verification: DGLocalVerification, expectedBotId: Int64?) -> Signal<DGLocalVerificationDetails?, NoError> {
    guard let username = usernames.first else { return .single(nil) }
    let remaining = Array(usernames.dropFirst())
    return localVerificationPeer(context: context, username: username)
    |> mapToSignal { peer -> Signal<DGLocalVerificationDetails?, NoError> in
        guard let peer, verification.referenceUserId == nil || peer.id.id._internalGetInt64Value() == verification.referenceUserId else {
            return localVerificationReferences(context: context, usernames: remaining, verification: verification, expectedBotId: expectedBotId)
        }
        return localVerificationDetails(context: context, peer: peer, expectedBotId: expectedBotId)
        |> mapToSignal { details in
            if let details { return .single(details) }
            return localVerificationReferences(context: context, usernames: remaining, verification: verification, expectedBotId: expectedBotId)
        }
    }
}

private func localVerificationSource(context: AccountContext, verification: DGLocalVerification, expectedBotId: Int64?) -> Signal<DGLocalVerificationDetails?, NoError> {
    guard let userId = verification.referenceUserId else {
        return localVerificationReferences(context: context, usernames: verification.referenceUsernames, verification: verification, expectedBotId: expectedBotId)
    }
    return context.engine.peers.findUserById(userId: userId)
    |> mapToSignal { peer -> Signal<DGLocalVerificationDetails?, NoError> in
        guard let peer else {
            return localVerificationReferences(context: context, usernames: verification.referenceUsernames, verification: verification, expectedBotId: expectedBotId)
        }
        return localVerificationDetails(context: context, peer: peer, expectedBotId: expectedBotId)
        |> mapToSignal { details in
            if let details { return .single(details) }
            return localVerificationReferences(context: context, usernames: verification.referenceUsernames, verification: verification, expectedBotId: expectedBotId)
        }
    }
}

private func localVerificationFromBot(context: AccountContext, verification: DGLocalVerification, expectedBotId: Int64?) -> Signal<DGLocalVerificationDetails?, NoError> {
    guard let username = verification.botUsername else { return .single(nil) }
    return localVerificationPeer(context: context, username: username)
    |> mapToSignal { bot -> Signal<DGLocalVerificationDetails?, NoError> in
        guard let bot, expectedBotId == nil || bot.id.id._internalGetInt64Value() == expectedBotId else { return .single(nil) }
        return localVerificationData(context: context, peer: bot)
        |> map { data in
            guard let settings = (data as? CachedUserData)?.botInfo?.verifierSettings, settings.iconFileId != 0 else { return nil }
            return DGLocalVerificationDetails(iconFileId: settings.iconFileId, botId: bot.id.id._internalGetInt64Value(), description: settings.customDescription ?? settings.companyName)
        }
    }
}

func donutgramLoadLocalVerification(context: AccountContext, verification: DGLocalVerification, expectedBotId: Int64? = nil) -> Signal<DGLocalVerificationDetails?, NoError> {
    guard verification != .none else { return .single(nil) }
    let expectedBotId = verification.verifierBotUserId ?? expectedBotId
    return localVerificationSource(context: context, verification: verification, expectedBotId: expectedBotId)
    |> mapToSignal { details in
        if let details { return .single(details) }
        return localVerificationFromBot(context: context, verification: verification, expectedBotId: expectedBotId)
    }
}
