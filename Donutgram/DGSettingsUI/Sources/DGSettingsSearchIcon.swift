import Foundation
import UIKit
import CoreText
import Display

private final class DGSearchIconMetrics {
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.width = width
    }
}

func dgSettingsSearchIcon(font: UIFont, color: UIColor) -> NSAttributedString {
    let configuration = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
    guard let symbol = UIImage(systemName: "magnifyingglass", withConfiguration: configuration) else {
        return NSAttributedString()
    }
    let ascent = font.ascender
    let descent = -font.descender
    let size = CGSize(width: ceil(symbol.size.width) + 2.0, height: ceil(max(ascent + descent + 2.0, symbol.size.height + 2.0)))
    guard let image = generateImage(size, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        UIGraphicsPushContext(context)
        symbol.draw(in: CGRect(x: floor((size.width - symbol.size.width) * 0.5), y: floor((size.height - symbol.size.height) * 0.5), width: symbol.size.width, height: symbol.size.height))
        UIGraphicsPopContext()
    })?.withRenderingMode(.alwaysTemplate) else {
        return NSAttributedString()
    }
    let metrics = Unmanaged.passRetained(DGSearchIconMetrics(ascent: ascent, descent: descent, width: size.width))
    var callbacks = CTRunDelegateCallbacks(
        version: kCTRunDelegateCurrentVersion,
        dealloc: { pointer in
            Unmanaged<DGSearchIconMetrics>.fromOpaque(pointer).release()
        },
        getAscent: { pointer in
            return Unmanaged<DGSearchIconMetrics>.fromOpaque(pointer).takeUnretainedValue().ascent
        },
        getDescent: { pointer in
            return Unmanaged<DGSearchIconMetrics>.fromOpaque(pointer).takeUnretainedValue().descent
        },
        getWidth: { pointer in
            return Unmanaged<DGSearchIconMetrics>.fromOpaque(pointer).takeUnretainedValue().width
        }
    )
    guard let delegate = CTRunDelegateCreate(&callbacks, metrics.toOpaque()) else {
        metrics.release()
        return NSAttributedString()
    }
    return NSAttributedString(string: "\u{FFFC}", attributes: [
        .font: font,
        .attachment: image,
        .foregroundColor: color,
        NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate
    ])
}
