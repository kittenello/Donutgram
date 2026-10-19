import Foundation
import AVFoundation
import CoreMedia

// PRODUCTION_HELPERS

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

// What AVCaptureAudioDataOutput delivers: interleaved signed 16-bit mono PCM at the route's sample rate.
func microphoneFormat(sampleRate: Double) -> CMAudioFormatDescription {
    var description = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )
    var layout = AudioChannelLayout()
    layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
    var format: CMAudioFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &description,
        layoutSize: MemoryLayout<AudioChannelLayout>.size,
        layout: &layout,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &format
    )
    precondition(status == noErr && format != nil)
    return format!
}

func sineBuffer(format: CMAudioFormatDescription, sampleRate: Double, startFrame: Int, frameCount: Int) -> CMSampleBuffer {
    var samples = [Int16](repeating: 0, count: frameCount)
    for i in 0 ..< frameCount {
        samples[i] = Int16(8000.0 * sin(2.0 * Double.pi * 440.0 * Double(startFrame + i) / sampleRate))
    }
    let byteCount = frameCount * 2
    var blockBuffer: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer
    )
    precondition(status == noErr)
    status = samples.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: byteCount)
    }
    precondition(status == noErr)
    var sampleBuffer: CMSampleBuffer?
    status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer!,
        formatDescription: format,
        sampleCount: frameCount,
        presentationTimeStamp: CMTime(value: CMTimeValue(startFrame), timescale: CMTimeScale(sampleRate)),
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
    )
    precondition(status == noErr)
    return sampleBuffer!
}

func makeWriter() -> (AVAssetWriter, URL) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    return (try! AVAssetWriter(url: url, fileType: .mp4), url)
}

// Writes two seconds of sound from the given microphone format with the settings the recorder picks, as it does.
func encodes(sampleRate: Double, settings: [String: Any], format: CMAudioFormatDescription) -> Bool {
    let (writer, url) = makeWriter()
    defer { try? FileManager.default.removeItem(at: url) }
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
        return false
    }
    writer.add(input)
    guard writer.startWriting() else {
        print("  startWriting failed: \(String(describing: writer.error))")
        return false
    }
    writer.startSession(atSourceTime: .zero)
    let chunk = Int(sampleRate / 50.0)
    var frame = 0
    while frame < Int(sampleRate * 2.0) {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard input.append(sineBuffer(format: format, sampleRate: sampleRate, startFrame: frame, frameCount: chunk)) else {
            print("  append failed: \(String(describing: writer.error))")
            return false
        }
        frame += chunk
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
        print("  finishWriting failed: \(String(describing: writer.error))")
        return false
    }
    let asset = AVURLAsset(url: url)
    let duration = CMTimeGetSeconds(asset.duration)
    return asset.tracks(withMediaType: .audio).count == 1 && duration > 1.8
}

let sampleRates: [Double] = [8_000, 16_000, 24_000, 44_100, 48_000]
print("sample rate | 64 kbps accepted | picked bit rate")
for sampleRate in sampleRates {
    let format = microphoneFormat(sampleRate: sampleRate)
    let (writer, url) = makeWriter()
    let canApply: ([String: Any]) -> Bool = { writer.canApply(outputSettings: $0, forMediaType: .audio) }
    let old: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: 64_000,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1
    ]
    let picked = roundVideoAudioSettings(formatDescription: format, canApply: canApply)
    try? FileManager.default.removeItem(at: url)
    let pickedBitRate = (picked?[AVEncoderBitRateKey] as? Int).map { "\($0)" } ?? (picked == nil ? "none" : "encoder default")
    print("\(Int(sampleRate)) Hz | \(canApply(old)) | \(pickedBitRate)")

    guard let picked else {
        check(false, "no AAC settings for \(Int(sampleRate)) Hz mono")
        continue
    }
    if sampleRate == 48_000 {
        check(picked[AVEncoderBitRateKey] as? Int == 64_000, "the built-in microphone keeps 64 kbps")
    }
    check(encodes(sampleRate: sampleRate, settings: picked, format: format), "\(Int(sampleRate)) Hz mono encodes to an mp4 with sound")
}

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("All round video audio checks passed.")
