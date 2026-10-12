import Foundation
import AVFAudio
import SwiftSignalKit
import TelegramCore

/// Keeps a sideloaded app running in the background by playing silence, mixed with other audio.
///
/// Telegram delivers message notifications through APNs, which never reach a build re-signed under another
/// bundle id. Without this the app is suspended a few seconds after leaving the foreground and drops its
/// connection, so no message arrives until it is opened again. `SharedWakeupManager` runs it only while the
/// app is in the background and nothing else holds the audio session.
final class DonutgramBackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var healthTimer: SwiftSignalKit.Timer?
    /// False while another Telegram audio holder owns the session; the health check must not take it back then.
    var canReclaimSession: () -> Bool = { true }

    var isActive: Bool {
        return self.player != nil
    }

    init() {
        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, let player = self.player else {
                return
            }
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }
            // A call or another non-mixable session paused the silence; resume it once that is over.
            if case .ended = type, self.canReclaimSession() {
                let _ = try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
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
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: silentWaveData())
            player.numberOfLoops = -1
            player.volume = 0.0
            guard player.play() else {
                Logger.shared.log("Wakeup", "Donutgram keep-alive: player did not start")
                return
            }
            self.player = player
            // Another holder deactivating the shared session (Telegram's own player finishing, for one) stops the
            // silence without an interruption notification, so check it periodically and restart it.
            let healthTimer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: { [weak self] in
                guard let self, let player = self.player, !player.isPlaying, self.canReclaimSession() else {
                    return
                }
                Logger.shared.log("Wakeup", "Donutgram keep-alive: restarting stopped player")
                let _ = try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                let _ = try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
            }, queue: Queue.mainQueue())
            self.healthTimer = healthTimer
            healthTimer.start()
            Logger.shared.log("Wakeup", "Donutgram keep-alive: started")
        } catch let e {
            Logger.shared.log("Wakeup", "Donutgram keep-alive: start failed: \(e)")
        }
    }

    /// `releaseSession` is false when another Telegram audio holder has taken the session meanwhile:
    /// deactivating it then would stop that holder's audio.
    func stop(releaseSession: Bool) {
        guard let player = self.player else {
            return
        }
        self.player = nil
        self.healthTimer?.invalidate()
        self.healthTimer = nil
        player.stop()
        if releaseSession {
            let session = AVAudioSession.sharedInstance()
            let _ = try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            let _ = try? session.setCategory(.soloAmbient)
        }
        Logger.shared.log("Wakeup", "Donutgram keep-alive: stopped")
    }
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
