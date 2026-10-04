import Foundation

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    precondition(value(), description)
}
func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.01 }

let normal = CGSize(width: 300.0, height: 380.0)
let minimumHeight: CGFloat = 74.0
let imageSizes = [CGSize(width: 800, height: 600), CGSize(width: 600, height: 1200), CGSize(width: 2400, height: 200)]
for availableWidth: CGFloat in [240, 320, 370, 500, 820] {
    for image in imageSizes {
        let captioned = donutgramChannelPhotoSizeLimit(defaultLimit: normal, availableWidth: availableWidth, imageSize: image, minimumHeight: minimumHeight, hasCaption: true)
        expect(close(captioned.width, availableWidth), "captioned photo must use the available post column")
        expect(close(captioned.height, normal.height), "wide photos retain the original maximum height")
        let standalone = donutgramChannelPhotoSizeLimit(defaultLimit: normal, availableWidth: availableWidth, imageSize: image, minimumHeight: minimumHeight, hasCaption: false)
        expect(standalone.width <= availableWidth, "standalone photo must fit the viewport")
        if image.height >= image.width {
            expect(close(standalone.width, min(availableWidth, normal.width)), "standalone portraits retain their normal width")
        }
        let height = donutgramChannelPhotoHeight(proposedHeight: 600, imageSize: image, defaultLimit: normal, minimumHeight: minimumHeight)
        expect(height >= minimumHeight && height <= normal.height, "widening must not create oversized photo heights")
    }
}
let panorama = donutgramChannelPhotoSizeLimit(defaultLimit: normal, availableWidth: 500, imageSize: CGSize(width: 2400, height: 200), minimumHeight: minimumHeight, hasCaption: false)
expect(panorama.width > normal.width, "standalone panoramas can expand beyond 300 points")
let clamped = donutgramChannelPhotoSizeLimit(defaultLimit: normal, availableWidth: -10, imageSize: imageSizes[0], minimumHeight: minimumHeight, hasCaption: true)
expect(clamped.width == 0, "invalid viewport width is clamped")
let zeroImage = donutgramChannelPhotoHeight(proposedHeight: 50, imageSize: .zero, defaultLimit: normal, minimumHeight: minimumHeight)
expect(zeroImage == minimumHeight, "missing dimensions must not divide by zero")
expect(donutgramChannelMosaicWidth(availableWidth: 370, defaultWidth: 300, measuredHeight: 900, maximumHeight: 380) == 300, "tall album refit retains ordinary width")
expect(donutgramChannelMosaicWidth(availableWidth: 240, defaultWidth: 300, measuredHeight: 900, maximumHeight: 380) == 240, "ordinary width floor cannot exceed a narrow viewport")
expect(donutgramChannelMosaicWidth(availableWidth: 500, defaultWidth: 300, measuredHeight: 200, maximumHeight: 380) == 500, "short album retains full column width")

let albums: [[CGSize]] = [
    [.init(width: 600, height: 600), .init(width: 600, height: 600)],
    [.init(width: 1600, height: 900), .init(width: 1600, height: 900)],
    [.init(width: 500, height: 1000), .init(width: 800, height: 600), .init(width: 600, height: 600)],
    Array(repeating: .init(width: 600, height: 600), count: 4),
    Array(repeating: .init(width: 600, height: 900), count: 10),
]
for availableWidth: CGFloat in [240, 370, 500, 820] {
    for images in albums {
        let initial = chatMessageBubbleMosaicLayout(maxSize: CGSize(width: availableWidth, height: normal.height), itemSizes: images)
        let fittedWidth = donutgramChannelMosaicWidth(availableWidth: availableWidth, defaultWidth: normal.width, measuredHeight: initial.1.height, maximumHeight: normal.height)
        let result = chatMessageBubbleMosaicLayout(maxSize: CGSize(width: fittedWidth, height: normal.height), itemSizes: images)
        expect(result.0.count == images.count, "all album images remain present")
        expect(result.1.width > 0 && result.1.width <= availableWidth + 1, "album width stays within the post column")
        expect(result.1.height.isFinite && result.1.height > 0, "album geometry stays finite")
        for (frame, _) in result.0 {
            expect(frame.width > 0 && frame.height > 0 && frame.minX >= 0 && frame.minY >= 0, "album tiles retain valid hit-test frames")
            expect(frame.maxX <= result.1.width + 1 && frame.maxY <= result.1.height + 1, "album tiles remain inside the album bounds")
        }
    }
}
let wideAlbum = chatMessageBubbleMosaicLayout(maxSize: CGSize(width: 370, height: 380), itemSizes: albums[0])
let ordinaryAlbum = chatMessageBubbleMosaicLayout(maxSize: normal, itemSizes: albums[0])
expect(wideAlbum.1.width > ordinaryAlbum.1.width, "square photo album expands beyond the old 300-point cap")
print("Passed \(checks) photo and album layout regression checks")
