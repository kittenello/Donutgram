import Foundation
// CGRect's members (midX, zero, maxY, offsetBy) come from the CoreGraphics overlay, which Foundation alone
// does not make visible in a single-file build.
import CoreGraphics

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

final class Layer {
    var alpha: CGFloat = 1.0
}

final class Node {
    var frame = CGRect.zero
    var alpha: CGFloat = 1.0
    var scale: CGFloat = 1.0
    let layer = Layer()
}

final class Rating {
    let view: Node? = Node()
}

struct Transition {
    func updateFrameAdditiveToCenter(node: Node, frame: CGRect) { node.frame = frame }
    func updateFrameAdditive(node: Node, frame: CGRect) { node.frame = frame }
    func updateFrameAdditive(view: Node, frame: CGRect) { view.frame = frame }
    func updateFrame(node: Node, frame: CGRect) { node.frame = frame }
    func updatePosition(node: Node, position: CGPoint) { node.frame.origin = position }
    func updateSublayerTransformScale(node: Node, scale: CGFloat) { node.scale = scale }
    func updateSublayerTransformScaleAdditive(node: Node, scale: CGFloat) { node.scale = scale }
    func updateAlpha(layer: Layer, alpha: CGFloat) { layer.alpha = alpha }
}

final class Header {
    let titleNodeRawContainer = Node()
    let titleNodeContainer = Node()
    let titleNode = Node()
    let subtitleNodeRawContainer = Node()
    let subtitleNodeContainer = Node()
    let subtitleNode = Node()
    let panelSubtitleNode = Node()
    let usernameNodeRawContainer = Node()
    let usernameNodeContainer = Node()
    let usernameNode = Node()
    let subtitleRating: Rating? = Rating()
    let subtitleBadgeView: Node? = Node()
    var isAvatarExpanded = false
    var navigationTransition: Bool?

    func update(titleSize: CGSize, subtitleSize: CGSize) {
        let transition = Transition()
        let titleFrame = CGRect(origin: CGPoint(x: (390.0 - titleSize.width) / 2.0, y: 200.0), size: titleSize)
        let subtitleFrame = CGRect(origin: CGPoint(x: (390.0 - subtitleSize.width) / 2.0, y: titleFrame.maxY + 1.0), size: subtitleSize)
        let usernameFrame = CGRect(origin: CGPoint(x: 195.0, y: titleFrame.maxY + 1.0), size: .zero)
        let expandedTitleScale: CGFloat = 0.8
        let transitionFraction: CGFloat = 0.0
        let transitionSourceTitleFrame = CGRect.zero
        let transitionSourceSubtitleFrame = CGRect.zero
        let titleHorizontalOffset: CGFloat = 0.0
        let titleExpandedHorizontalOffset: CGFloat = 0.0
        let titleCollapseFraction: CGFloat = 0.0
        let titleMinScale: CGFloat = 0.6
        let subtitleMinScale: CGFloat = 0.8
        let titleOffset: CGFloat = 0.0
        let apparentTitleLockOffset: CGFloat = 0.0
        let subtitleOffset: CGFloat = 0.0
        let panelSubtitleOffset: CGFloat = 0.0
        let subtitleAlpha: CGFloat = 1.0
        let subtitleBadgeSize: CGSize? = CGSize(width: 20.0, height: 20.0)
        let subtitleRatingSize: CGSize? = CGSize(width: 30.0, height: 30.0)
        let subtitleRatingInset: CGFloat = 29.0
        fatalError("production layout")
    }

    func verify(titleSize: CGSize, subtitleSize: CGSize) {
        update(titleSize: titleSize, subtitleSize: subtitleSize)
        let expectedCenter = CGPoint(x: 195.0, y: 201.0 + titleSize.height + subtitleSize.height / 2.0)
        precondition(subtitleNodeContainer.frame.origin == expectedCenter, "status must stay below the avatar even when the name has no glyphs")
        precondition(titleNodeContainer.frame.origin.x == 195.0, "name container must remain centered")
        precondition(titleNodeContainer.scale.isFinite && titleNodeContainer.scale > 0.0)
        precondition(subtitleNodeContainer.scale.isFinite && subtitleNodeContainer.scale > 0.0)
        let ratingFrame = subtitleRating!.view!.frame
        precondition(ratingFrame.width == 30.0 && ratingFrame.height == 30.0)
        precondition(ratingFrame.minX == -subtitleSize.width / 2.0 - 29.0, "rating must follow the status width")
        precondition(ratingFrame.midY == 0.0, "rating must align vertically with status")
        precondition(expectedCenter.y + ratingFrame.midY > 200.0)
    }
}

var count = 0
for expanded in [false, true] {
    for navigating in [false, true] {
        for titleSize in [CGSize(width: 120.0, height: 34.0), CGSize(width: 0.0, height: 34.0), .zero] {
            let header = Header()
            header.isAvatarExpanded = expanded
            header.navigationTransition = navigating ? true : nil
            for subtitleSize in [CGSize(width: 60.0, height: 20.0), CGSize(width: 170.0, height: 20.0), .zero, CGSize(width: 60.0, height: 20.0)] {
                header.verify(titleSize: titleSize, subtitleSize: subtitleSize)
                count += 1
            }
        }
    }
}
print("profile header layout: \(count) cases passed")
