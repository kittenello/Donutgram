import Foundation
import Postbox
import SwiftSignalKit

public extension TelegramEngine.Messages {
    func enqueueConfirmedUnpaidPluginText(to peerId: EnginePeer.Id, threadId: Int64?, text: String, isCurrent: @escaping () -> Bool) -> Signal<Bool, NoError> {
        guard !text.isEmpty, text.utf16.count <= 4096 else { return .single(false) }
        return self.account.postbox.transaction { transaction -> Bool in
            guard isCurrent(), let peer = transaction.getPeer(peerId), !isServicePeer(peer), !(peer is TelegramSecretChat) else { return false }
            if let user = peer as? TelegramUser {
                guard user.botInfo == nil, let cached = transaction.getPeerCachedData(peerId: peerId) as? CachedUserData, cached.sendPaidMessageStars == nil else { return false }
            } else if let channel = peer as? TelegramChannel {
                guard !channel.isMonoForum, channel.sendPaidMessageStars == nil else { return false }
            } else if !(peer is TelegramGroup) { return false }
            let message = EnqueueMessage.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            guard isCurrent() else { return false }
            return enqueueMessages(transaction: transaction, account: self.account, peerId: peerId, messages: [(false, message)]).contains(where: { $0 != nil })
        }
    }
}
