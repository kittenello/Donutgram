import Foundation
import Postbox
import DGSimpleSettings

/// The set of a sticker this account sent with «Анонимная отправка стикеров»: the server's copy has none, so a tap and
/// «Посмотреть набор» open the one kept on this device. Nil for any other file.
public func donutgramAnonymousStickerPack(accountPeerId: PeerId, file: TelegramMediaFile) -> StickerPackReference? {
    guard file.isSticker, file.fileId.namespace == Namespaces.Media.CloudFile, let data = DGSimpleSettings.shared.anonymousStickerPackData(accountId: accountPeerId.toInt64(), fileId: file.fileId.id) else {
        return nil
    }
    return try? JSONDecoder().decode(StickerPackReference.self, from: data)
}

/// Keeps the set `reference` of a sticker sent without it: `file` is the server's copy.
func donutgramSaveAnonymousStickerPack(_ reference: StickerPackReference, accountPeerId: PeerId, file: TelegramMediaFile) {
    guard file.fileId.namespace == Namespaces.Media.CloudFile else {
        return
    }
    switch reference {
    case .id, .name:
        guard let data = try? JSONEncoder().encode(reference) else {
            return
        }
        DGSimpleSettings.shared.setAnonymousStickerPackData(data, accountId: accountPeerId.toInt64(), fileId: file.fileId.id)
    default:
        break
    }
}
