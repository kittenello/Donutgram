import Foundation
import AVFAudio
import SwiftSignalKit
import TelegramCore

/// Keeps a sideloaded app running in the background by playing silence, mixed with other audio.
///
/// Telegram delivers message notifications through APNs, which never reach a build re-signed under another
/// bundle id. Without this the app is suspended a few seconds after leaving the foreground and drops its
/// connection, so no message arrives until it is opened again. `SharedWakeupManager` runs it only while the
/// app is in the background and Telegram's own audio (`ManagedAudioSession`, calls) does not hold the session.
///
/// It shares `AVAudioSession.sharedInstance()` with `ManagedAudioSession` without going through it. That is safe
/// because the two never own the session at once: this starts only after `ManagedAudioSession` reports itself
/// inactive, which it does after `applyNone` has deactivated the session and dropped its cached category, so its
/// next `setup` sets its own category again rather than inheriting ours.
final class DonutgramBackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var previousConfiguration: KeepAliveSessionConfiguration?
    private var interruptionObserver: NSObjectProtocol?
    private var healthTimer: SwiftSignalKit.Timer?
    /// False while Telegram's own audio holds the session; the keep-alive must not take it back then.
    var canReclaimSession: () -> Bool = { true }

    var isActive: Bool {
        return self.player != nil
    }

    init() {
        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, self.player != nil else {
                return
            }
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }
            // A phone call or an alarm paused the silence; resume it as soon as that is over.
            if case .ended = type {
                self.resumeIfStopped()
            }
        })
    }

    deinit {
        if let interruptionObserver = self.interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        self.healthTimer?.invalidate()
        self.player?.stop()
    }

    func start() {
        if self.player != nil {
            return
        }
        let session = AVAudioSession.sharedInstance()
        let previousConfiguration = KeepAliveSessionConfiguration(category: session.category, mode: session.mode, options: session.categoryOptions)
        guard let player = makePlayingSilence() else {
            restoreSession(previousConfiguration)
            return
        }
        self.player = player
        self.previousConfiguration = previousConfiguration

        // The session can stop without an interruption notification, for one when another holder deactivates
        // it or media services are reset, so check it periodically and restart it.
        let healthTimer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: { [weak self] in
            self?.resumeIfStopped()
        }, queue: Queue.mainQueue())
        self.healthTimer = healthTimer
        healthTimer.start()
        Logger.shared.log("Wakeup", "Donutgram keep-alive: started")
    }

    /// `releaseSession` is false when Telegram's own audio has taken the session meanwhile: deactivating it or
    /// changing its category then would break that audio.
    func stop(releaseSession: Bool) {
        guard let player = self.player else {
            return
        }
        self.player = nil
        self.healthTimer?.invalidate()
        self.healthTimer = nil
        player.stop()
        if releaseSession, let previousConfiguration = self.previousConfiguration {
            restoreSession(previousConfiguration)
        }
        self.previousConfiguration = nil
        Logger.shared.log("Wakeup", "Donutgram keep-alive: stopped")
    }

    private func resumeIfStopped() {
        guard let player = self.player, !player.isPlaying, self.canReclaimSession() else {
            return
        }
        Logger.shared.log("Wakeup", "Donutgram keep-alive: restarting stopped player")
        player.stop()
        // A reset of media services invalidates the player itself, so build a new one.
        if let replacement = makePlayingSilence() {
            self.player = replacement
        }
    }
}

private func makePlayingSilence() -> AVAudioPlayer? {
    let session = AVAudioSession.sharedInstance()
    do {
        // Mixable, so it neither interrupts other apps' audio nor takes the lock screen's Now Playing controls,
        // and it may be activated from the background.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let player = try AVAudioPlayer(data: silentWaveData())
        player.numberOfLoops = -1
        if player.play() {
            return player
        }
        Logger.shared.log("Wakeup", "Donutgram keep-alive: player did not start")
    } catch let e {
        Logger.shared.log("Wakeup", "Donutgram keep-alive: start failed: \(e)")
    }
    return nil
}

private struct KeepAliveSessionConfiguration {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}

/// Deactivates the session and puts back the configuration it had before the keep-alive took it.
private func restoreSession(_ configuration: KeepAliveSessionConfiguration) {
    let session = AVAudioSession.sharedInstance()
    let _ = try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    let _ = try? session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
}

/// One second of 8 kHz 16-bit mono silence as a WAV file.
private func silentWaveData() -> Data {
    let sampleRate: UInt32 = 8000
    let bytesPerSample: UInt16 = 2
    let sampleCount: UInt32 = sampleRate
    let dataSize = sampleCount * UInt32(bytesPerSample)

    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36) + dataSize)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(sampleRate)
    append(sampleRate * UInt32(bytesPerSample))
    append(bytesPerSample)
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(dataSize)
    data.append(Data(count: Int(dataSize)))
    return data
}
