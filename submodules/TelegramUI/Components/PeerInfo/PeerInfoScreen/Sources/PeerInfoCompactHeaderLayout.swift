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

    func balanceFrame(size: CGSize, hasMusic: Bool) -> CGRect {
        return CGRect(origin: CGPoint(x: hasMusic ? self.row.maxX - size.width : self.row.midX - size.width * 0.5, y: self.row.minY), size: size)
    }

    func musicFrame(size: CGSize, hasBalance: Bool) -> CGRect {
        return CGRect(origin: CGPoint(x: hasBalance ? self.row.minX : self.row.midX - size.width * 0.5, y: self.row.minY), size: size)
    }
}
