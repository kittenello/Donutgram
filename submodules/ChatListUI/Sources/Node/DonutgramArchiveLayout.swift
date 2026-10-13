import Foundation

func donutgramArchiveRestoredOffset(_ offset: CGFloat, hideArchive: Bool, hasStories: Bool) -> CGFloat {
    return hideArchive && !hasStories ? max(0.0, offset) : offset
}

func donutgramArchiveTopGapNeedsReset(hideArchive: Bool, isRoot: Bool, isTracking: Bool, isDecelerating: Bool, storiesInset: CGFloat, offset: CGFloat?, removedArchive: Bool) -> Bool {
    guard hideArchive, isRoot, !isTracking, !isDecelerating, storiesInset == 0.0, let offset else {
        return false
    }
    return offset < -1.0 || (removedArchive && offset <= 0.0)
}
