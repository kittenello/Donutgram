import Foundation

public protocol OverlayAudioPlayerController: AnyObject {
    /// Donutgram: called once when the player screen closes.
    var donutgramDismissed: (() -> Void)? { get set }
}
