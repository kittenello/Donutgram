import Foundation
import AVFoundation
import CoreMedia
import TelegramCore

// Donutgram: the round video recorder's lines in the app log (sent from Debug ▸ Send Logs), so a round video that closes
// by itself can be told apart without a device attached: which microphone format it got, the sound settings it picked,
// and the writer's error.
func roundVideoRecorderLog(_ text: @autoclosure () -> String) {
    Logger.shared.log("RoundVideoRecorder", text())
}

// "16000 Hz, 1 ch" for the sound samples described by `formatDescription`.
func roundVideoAudioFormatSummary(_ formatDescription: CMFormatDescription?) -> String {
    guard let formatDescription, let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
        return "unknown format"
    }
    return "\(Int(streamDescription.pointee.mSampleRate)) Hz, \(streamDescription.pointee.mChannelsPerFrame) ch"
}

// "bit rate 48000" for the writer's sound settings, or "bit rate encoder default" when they leave it to the encoder.
func roundVideoAudioSettingsSummary(_ settings: [String: Any]) -> String {
    if let bitRate = settings[AVEncoderBitRateKey] as? Int {
        return "bit rate \(bitRate)"
    }
    return "bit rate encoder default"
}
