import Foundation
import Postbox
import DGSimpleSettings

/// Ghost mode with story view receipts turned off, the check `_internal_markStoryAsSeen` makes
/// before it queues a receipt.
func donutgramGhostModeBlocksStoryReads() -> Bool {
    let settings = DGSimpleSettings.shared
    return settings.ghostModeEnabled && !settings.ghostReadStories
}

/// Whether `messages` are screenshot notifications that ghost mode drops. A screenshot of
/// view-once media in a chat, or of a secret chat, queues a `historyScreenshot` message,
/// and the other side gets "took a screenshot": the same signal as a read receipt for that
/// content. Both kinds are queued through `enqueueMessages(transaction:...)`, which drops them.
func donutgramGhostModeDropsScreenshotNotifications(_ messages: [(Bool, EnqueueMessage)]) -> Bool {
    if messages.isEmpty || !donutgramGhostModeBlocksContentReads() {
        return false
    }
    return messages.allSatisfy { entry -> Bool in
        if case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = entry.1, let action = mediaReference?.media as? TelegramMediaAction, case .historyScreenshot = action.action {
            return true
        }
        return false
    }
}
