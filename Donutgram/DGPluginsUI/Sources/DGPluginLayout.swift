import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct DGPluginCardLayout {
    let icon: CGRect
    let title: CGRect
    let subtitle: CGRect
    let headingButton: CGRect
    let toggle: CGRect
    let description: CGRect
    let separator: CGRect
    let actions: [CGRect]
    let height: CGFloat

    init(width: CGFloat, titleHeight: CGFloat, subtitleHeight: CGFloat, descriptionHeight: CGFloat, actionLabelHeight: CGFloat) {
        let headingHeight = max(44, titleHeight + 3 + subtitleHeight)
        self.icon = CGRect(x: 16, y: 14, width: 44, height: 44)
        let textWidth = max(1, width - 151)
        self.title = CGRect(x: 72, y: 14, width: textWidth, height: titleHeight)
        self.subtitle = CGRect(x: 72, y: self.title.maxY + 3, width: textWidth, height: subtitleHeight)
        self.headingButton = CGRect(x: 0, y: 0, width: max(1, width - 75), height: headingHeight + 23)
        self.toggle = CGRect(x: width - 67, y: 14 + max(0, (headingHeight - 31) / 2), width: 51, height: 31)
        self.description = CGRect(x: 16, y: 14 + headingHeight + 9, width: max(1, width - 32), height: descriptionHeight)
        self.separator = CGRect(x: 16, y: self.description.maxY + 9, width: max(1, width - 32), height: 1)
        let actionWidth = max(1, (width - 32) / 3)
        let actionHeight = max(48, 18 + 4 + actionLabelHeight + 10)
        let actionY = self.separator.minY
        self.actions = (0 ..< 3).map { CGRect(x: 16 + CGFloat($0) * actionWidth, y: actionY, width: actionWidth, height: actionHeight) }
        self.height = actionY + actionHeight + 4
    }
}

public func dgIsPluginDocument(fileName: String) -> Bool {
    let name = fileName.lowercased()
    return name.hasSuffix(".dgplugin") || name.hasSuffix(".donut.js")
}
