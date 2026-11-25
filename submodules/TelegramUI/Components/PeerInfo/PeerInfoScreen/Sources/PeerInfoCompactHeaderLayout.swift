import Foundation
import CoreGraphics

struct PeerInfoCompactHeaderLayout {
    let row: CGRect
    let spacing: CGFloat = 6.0

    init(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, top: CGFloat) {
        self.row = CGRect(x: leftInset + 16.0, y: top, width: max(1.0, width - leftInset - rightInset - 32.0), height: 20.0)
    }

    func maximumBalanceWidth(hasMusic: Bool) -> CGFloat {
        return self.row.width * (hasMusic ? 0.45 : 1.0)
    }

    func musicWidth(balanceWidth: CGFloat) -> CGFloat {
        return max(1.0, self.row.width - balanceWidth - (balanceWidth > 0.0 ? self.spacing : 0.0))
    }

    func frames(musicSize: CGSize?, balanceSize: CGSize?) -> (music: CGRect?, balance: CGRect?) {
        let musicWidth = musicSize?.width ?? 0.0
        let balanceWidth = balanceSize?.width ?? 0.0
        let spacing = musicSize != nil && balanceSize != nil ? self.spacing : 0.0
        let startX = self.row.midX - (musicWidth + spacing + balanceWidth) * 0.5
        let centerY = self.row.minY + max(musicSize?.height ?? 0.0, balanceSize?.height ?? 0.0) * 0.5
        let music = musicSize.map { CGRect(x: startX, y: centerY - $0.height * 0.5, width: $0.width, height: $0.height) }
        let balance = balanceSize.map { CGRect(x: startX + musicWidth + spacing, y: centerY - $0.height * 0.5, width: $0.width, height: $0.height) }
        return (music, balance)
    }
}
