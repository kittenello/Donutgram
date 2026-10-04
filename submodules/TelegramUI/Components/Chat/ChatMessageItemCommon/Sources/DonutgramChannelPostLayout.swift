import Foundation

/// Captions can use the whole column. A standalone portrait keeps its ordinary
/// width; a wide standalone photo can grow without making it unnecessarily tall.
public func donutgramChannelPhotoSizeLimit(defaultLimit: CGSize, availableWidth: CGFloat, imageSize: CGSize, minimumHeight: CGFloat, hasCaption: Bool) -> CGSize {
    var result = defaultLimit
    result.width = max(0.0, availableWidth)
    if !hasCaption, imageSize.width > 0.0, imageSize.height > 0.0 {
        let widthAtMinimumHeight = minimumHeight * imageSize.width / imageSize.height
        result.width = min(result.width, max(defaultLimit.width, widthAtMinimumHeight))
    }
    return result
}

/// Enlarging a photo's width must not enlarge the post's original height limit.
public func donutgramChannelPhotoHeight(proposedHeight: CGFloat, imageSize: CGSize, defaultLimit: CGSize, minimumHeight: CGFloat) -> CGFloat {
    guard imageSize.width > 0.0, imageSize.height > 0.0 else {
        return max(minimumHeight, proposedHeight)
    }
    let scale = min(defaultLimit.width / imageSize.width, defaultLimit.height / imageSize.height)
    return max(minimumHeight, min(proposedHeight, imageSize.height * scale))
}

/// Refit tall album mosaics while keeping the ordinary album width as a floor.
public func donutgramChannelMosaicWidth(availableWidth: CGFloat, defaultWidth: CGFloat, measuredHeight: CGFloat, maximumHeight: CGFloat) -> CGFloat {
    let width = max(0.0, availableWidth)
    guard measuredHeight > maximumHeight, measuredHeight > 0.0 else {
        return width
    }
    return min(width, max(defaultWidth, floor(width * maximumHeight / measuredHeight)))
}

/// The mosaic rounds each tile up; reserve any resulting overflow before refitting.
public func donutgramChannelMosaicWidthAfterRounding(inputWidth: CGFloat, measuredWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
    let overflow = max(0.0, measuredWidth - max(0.0, availableWidth))
    return max(0.0, floor(inputWidth - overflow))
}
