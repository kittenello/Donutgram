import Postbox
import DGSimpleSettings

public func donutgramShouldHideServiceMessage(_ message: Message) -> Bool {
    guard DGSimpleSettings.shared.hideServiceMessages else {
        return false
    }
    return message.media.contains { $0 is TelegramMediaAction }
}
