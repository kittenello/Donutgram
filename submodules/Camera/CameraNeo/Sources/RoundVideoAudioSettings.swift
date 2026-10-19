import Foundation
import AVFoundation
import CoreMedia

// Donutgram: the AAC bit rates tried for a round video's sound, best first. 64 kbps is what the built-in microphone
// (48 kHz) records at. A headset microphone is much slower: a Bluetooth headset in a call-style route delivers 8, 16 or
// 24 kHz mono, and the AAC encoder refuses 64 kbps at those rates. The recorder used to give up the whole recording on
// that refusal, so a round video started with headphones closed after a moment.
let roundVideoAudioBitRates: [Int] = [64_000, 48_000, 32_000, 24_000, 16_000, 12_000, 8_000]

// The AAC settings for the microphone samples described by `formatDescription`, or nil if the encoder accepts none.
// `canApply` is the writer's own check, so the choice follows the encoder actually in use. The last resort leaves the bit
// rate to the encoder.
func roundVideoAudioSettings(
    formatDescription: CMFormatDescription,
    canApply: ([String: Any]) -> Bool
) -> [String: Any]? {
    var baseSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC
    ]
    if let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
        baseSettings[AVSampleRateKey] = streamDescription.pointee.mSampleRate
        baseSettings[AVNumberOfChannelsKey] = streamDescription.pointee.mChannelsPerFrame
    }

    var channelLayoutSize = 0
    if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &channelLayoutSize), channelLayoutSize > 0 {
        baseSettings[AVChannelLayoutKey] = Data(bytes: channelLayout, count: channelLayoutSize)
    }

    for bitRate in roundVideoAudioBitRates {
        var settings = baseSettings
        settings[AVEncoderBitRateKey] = bitRate
        if canApply(settings) {
            return settings
        }
    }
    if canApply(baseSettings) {
        return baseSettings
    }
    return nil
}
