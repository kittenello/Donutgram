import Foundation
import Postbox
import DGSimpleSettings

public func donutgramAnonymousStickerPack(accountPeerId: PeerId, messageId: MessageId) -> StickerPackReference? {
    guard let data = DGSimpleSettings.shared.anonymousStickerPackData(accountId: accountPeerId.toInt64(), peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, messageId: messageId.id) else {
        return nil
    }
    return try? JSONDecoder().decode(StickerPackReference.self, from: data)
}

func donutgramSaveAnonymousStickerPack(_ reference: StickerPackReference, accountPeerId: PeerId, messageId: MessageId) {
    switch reference {
    case .id, .name:
        guard let data = try? JSONEncoder().encode(reference) else {
            return
        }
        DGSimpleSettings.shared.setAnonymousStickerPackData(data, accountId: accountPeerId.toInt64(), peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, messageId: messageId.id)
    default:
        break
    }
}
