import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

var cases = 0
for width in stride(from: CGFloat(200), through: 1024, by: 16) {
    for scale in [CGFloat(0.8), 1, 1.25, 1.5, 2] {
        for lines in [CGFloat(1), 2] {
            let titleHeight = 21 * scale * lines
            let subtitleHeight = 15 * scale * lines
            let descriptionHeight = 18 * scale * lines
            let actionLabelHeight = 14 * scale * lines
            let layout = DGPluginCardLayout(width: width, titleHeight: titleHeight, subtitleHeight: subtitleHeight, descriptionHeight: descriptionHeight, actionLabelHeight: actionLabelHeight)
            let bounds = CGRect(x: 0, y: 0, width: width, height: layout.height)
            for frame in [layout.icon, layout.title, layout.subtitle, layout.headingButton, layout.toggle, layout.description, layout.separator] + layout.actions {
                precondition(frame.width > 0 && frame.height > 0 && bounds.contains(frame), "plugin controls must stay within their row")
            }
            precondition(layout.icon.maxX < layout.title.minX)
            precondition(layout.title.maxX < layout.toggle.minX)
            precondition(!layout.headingButton.intersects(layout.toggle), "opening details must not toggle the plugin")
            precondition(layout.title.maxY < layout.subtitle.minY)
            precondition(layout.subtitle.maxY < layout.description.minY)
            precondition(layout.description.maxY < layout.separator.minY)
            precondition(layout.actions.count == 3)
            for action in layout.actions {
                precondition(action.width >= 44 && action.height >= max(44, actionLabelHeight + 32))
                precondition(action.minY >= layout.description.maxY)
            }
            precondition(layout.actions[0].maxX <= layout.actions[1].minX + 0.001)
            precondition(layout.actions[1].maxX <= layout.actions[2].minX + 0.001)
            cases += 1
        }
    }
}
for name in ["plugin.dgplugin", "PLUGIN.DGPLUGIN", "plugin.donut.js", "plugin.DONUT.JS"] { precondition(dgIsPluginDocument(fileName: name)) }
for name in ["", "plugin.js", "plugin.dgplugin.exe", "plugin.donut.js.mp4", "plugin.dgplugin "] { precondition(!dgIsPluginDocument(fileName: name)) }
print("plugin layout: \(cases) measured-text layouts and document extensions passed; UIKit rendering was not exercised")
