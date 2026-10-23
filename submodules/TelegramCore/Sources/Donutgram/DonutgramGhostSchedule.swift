import Foundation
import Postbox
internal import TelegramApi

/// Whether the server kept a just-sent message scheduled instead of posting it at once.
/// `serverMessage` is the message returned in `result`, if any, and `serverTimestamp` is
/// the date the server gave the sent message. Only non-ghost messages use the date.
///
/// Stock Telegram decides this by comparing the stored schedule date with the returned
/// date, since the server posts a message dated less than 10 seconds ahead right away.
/// A ghost-mode message is sent with a date refreshed at request time
/// (`OutgoingScheduleInfoMessageAttribute.effectiveScheduleTime`), so its two dates
/// usually differ even when the server did schedule it. The date check would then store
/// it as a posted message, and the real one would arrive later as a duplicate. For such
/// a message this checks whether the server returned it as scheduled.
func donutgramSentMessageIsScheduled(_ message: Message, serverMessage: Api.Message?, serverTimestamp: Int32?, result: Api.Updates) -> Bool {
    guard let attribute = message.attributes.first(where: { $0 is OutgoingScheduleInfoMessageAttribute }) as? OutgoingScheduleInfoMessageAttribute else {
        return false
    }
    if !attribute.isGhostScheduled {
        return attribute.scheduleTime == serverTimestamp
    }
    guard let serverMessageId = serverMessage?.id() else {
        return false
    }
    for update in result.allUpdates {
        if case let .updateNewScheduledMessage(updateNewScheduledMessageData) = update, updateNewScheduledMessageData.message.id() == serverMessageId {
            return true
        }
    }
    return false
}
