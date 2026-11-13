import AVFoundation
import Foundation

/// Turns a finished WAV recording into a small .m4a for keeping and sending. The WAV is the safe
/// form while recording; once the note is finished the compressed copy takes its place. If anything
/// here fails the WAV simply stays.
enum AudioCompressor {
    enum Failure: Error {
        case buffer
        case short
    }

    /// Writes `m4a` from `wav`. Throws unless the result can be read back at about the same length.
    static func compress(wav: URL, to m4a: URL) throws {
        try? FileManager.default.removeItem(at: m4a)
        let input = try AVAudioFile(forReading: wav)
        let format = input.processingFormat
        let frames = input.length
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVEncoderBitRateKey: 32_000,
            ]
            let output = try AVAudioFile(forWriting: m4a, settings: settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { throw Failure.buffer }
            while input.framePosition < frames {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
            output.close()
        }
        // Believe the copy only if it reads back at about the length of the original.
        let check = try AVAudioFile(forReading: m4a)
        let original = Double(frames) / format.sampleRate
        let copy = Double(check.length) / check.processingFormat.sampleRate
        guard original > 0, copy >= original * 0.95 else {
            try? FileManager.default.removeItem(at: m4a)
            throw Failure.short
        }
    }
}
