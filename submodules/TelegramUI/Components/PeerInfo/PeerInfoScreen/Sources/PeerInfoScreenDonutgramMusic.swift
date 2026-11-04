import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import UniversalMediaPlayer

/// Donutgram («Не включать музыку автоматически»): the profile's pinned music opens on a paused player. Call the
/// returned closure when the player screen closes: if nothing was played meanwhile, the paused player stops too, so
/// no music bar is left behind.
func donutgramStopUnplayedProfileMusic(context: AccountContext, peerId: EnginePeer.Id) -> () -> Void {
    let didPlay = Atomic<Bool>(value: false)
    let playbackDisposable = (context.sharedContext.mediaManager.globalMediaPlayerState
    |> deliverOnMainQueue).startStrict(next: { stateAndType in
        guard let (_, stateOrLoading, type) = stateAndType, type == .music, case let .state(state) = stateOrLoading else {
            return
        }
        if donutgramIsPlaying(state.status.status) {
            let _ = didPlay.swap(true)
        }
    })
    return {
        playbackDisposable.dispose()
        if didPlay.with({ $0 }) {
            return
        }
        let _ = (context.sharedContext.mediaManager.globalMediaPlayerState
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { stateAndType in
            guard let (account, stateOrLoading, type) = stateAndType, type == .music, account.peerId == context.account.peerId, case let .state(state) = stateOrLoading, !donutgramIsPlaying(state.status.status) else {
                return
            }
            guard let location = state.playlistLocation as? PeerMessagesPlaylistLocation, case let .savedMusic(savedMusicContext, _, _) = location, savedMusicContext.peerId == peerId else {
                return
            }
            context.sharedContext.mediaManager.setPlaylist(nil, type: .music, control: .playback(.pause))
        })
    }
}

private func donutgramIsPlaying(_ status: MediaPlayerPlaybackStatus) -> Bool {
    switch status {
    case .playing:
        return true
    case let .buffering(_, whilePlaying, _, _):
        return whilePlaying
    case .paused:
        return false
    }
}
