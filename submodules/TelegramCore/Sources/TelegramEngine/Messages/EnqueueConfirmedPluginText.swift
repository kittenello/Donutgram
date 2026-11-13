import Foundation
import Postbox
import SwiftSignalKit

public extension TelegramEngine.Messages {
    /// Enqueues an ordinary unpaid text message for a Donutgram plugin. `sendAsPeerId` is the identity chosen in the
    /// chat's "send as" selector (`ChatPresentationInterfaceState.currentSendAsPeerId`): the chat's own send path
    /// attaches it to every message, so without it a plugin would post from the personal account in a group where the
    /// user writes as a channel. An identity that is no longer known refuses the send instead of falling back.
    /// `threadReply` is the reply to the open topic's or comment thread's root that the chat's own send path adds:
    /// the server files a message into a thread only through its reply, so `threadId` alone would land it in General.
    func enqueueConfirmedUnpaidPluginText(to peerId: EnginePeer.Id, threadId: Int64?, threadReply: EngineMessageReplySubject?, text: String, sendAsPeerId: EnginePeer.Id?, isCurrent: @escaping () -> Bool) -> Signal<Bool, NoError> {
        guard !text.isEmpty, text.utf16.count <= 4096 else { return .single(false) }
        return self.account.postbox.transaction { transaction -> Bool in
            guard isCurrent(), let peer = transaction.getPeer(peerId), !isServicePeer(peer), !(peer is TelegramSecretChat) else { return false }
            if let user = peer as? TelegramUser {
                guard user.botInfo == nil, let cached = transaction.getPeerCachedData(peerId: peerId) as? CachedUserData, cached.sendPaidMessageStars == nil else { return false }
            } else if let channel = peer as? TelegramChannel {
                guard !channel.isMonoForum, channel.sendPaidMessageStars == nil else { return false }
            } else if !(peer is TelegramGroup) { return false }
            if let threadReply, threadReply.messageId.peerId != peerId { return false }
            var attributes: [MessageAttribute] = []
            if let sendAsPeerId {
                guard transaction.getPeer(sendAsPeerId) != nil else { return false }
                attributes.append(SendAsMessageAttribute(peerId: sendAsPeerId))
            }
            let message = EnqueueMessage.message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: threadReply, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            guard isCurrent() else { return false }
            return enqueueMessages(transaction: transaction, account: self.account, peerId: peerId, messages: [(false, message)]).contains(where: { $0 != nil })
        }
    }
}
