import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudioIntakeError: LocalizedError, Equatable {
    case vorbis
    case otherOgg
    case webm
    case noSoundtrack(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .vorbis:
            return "This is Ogg Vorbis audio, which this device has no decoder for yet. Ogg Opus (WhatsApp), MP3, M4A, WAV, FLAC, AIFF and the sound of MP4 and MOV videos work."
        case .otherOgg:
            return "This Ogg file holds audio this device has no decoder for yet; of Ogg files, only Opus (WhatsApp's voice notes) can be read."
        case .webm:
            return "WebM and Matroska files are not supported yet. Ogg Opus (WhatsApp), MP3, M4A, WAV, FLAC, AIFF and the sound of MP4 and MOV videos work."
        case .noSoundtrack(let name):
            return "\(name) has no sound to transcribe."
        case .unreadable(let name):
            return "\(name) could not be read as audio or video. It may be damaged, or in a format this device does not know."
        }
    }
}

/// One way in for every file the app is given (the Files sheet, the share sheet): what it is, from its bytes
/// (`AudioSniffer`), and, when the pipeline cannot read it as it is, a 16-bit WAV beside it that it can.
///
/// - Ogg Opus (WhatsApp): our own Ogg reader into Apple's Opus decoder (`OggOpusDecoder`).
/// - Audio that `AVAudioFile` opens (MP3, M4A, WAV, AIFF, CAF, FLAC): kept as it is.
/// - Anything else AVFoundation opens, the soundtrack of MP4, MOV and 3GP video among it: read with
///   `AVAssetReader`, streamed to a 16 kHz mono WAV, never loaded whole.
/// - Ogg Vorbis, WebM and Matroska: a plain message; there is no Apple decoder, and no third-party code
///   without the owner's agreement.
enum AudioIntake {
    /// WhatsApp's voice notes: Opus in Ogg, named `.opus` (or `.ogg` by some apps).
    static let opus: UTType = UTType(filenameExtension: "opus", conformingTo: .audio) ?? .audio
    static let ogg: UTType = UTType(filenameExtension: "ogg", conformingTo: .audio) ?? .audio

    /// What the Files sheet offers: any audio, any film (for its soundtrack), and the two Ogg types in case
    /// the system does not count them as audio.
    static var importableTypes: [UTType] {
        var types: [UTType] = [.audio, .movie, .audiovisualContent]
        for type in [opus, ogg] where !types.contains(type) { types.append(type) }
        return types
    }

    /// The rate and channels of a soundtrack taken out of a video: what the speech model wants, and small.
    static let extractedRate = 16_000.0

    /// What happened to a file on its way in.
    struct Prepared: Equatable, Sendable {
        var container: AudioContainer
        /// The WAV to use in place of the original, or nil when the original is read as it is.
        var wav: URL?
        var seconds: Double?
        var hadVideo: Bool

        /// A short line for the run's step record.
        var summary: String {
            let length = seconds.map { String(format: "%.1f s", $0) } ?? "unknown length"
            if wav == nil { return "\(container.name), read as it is (\(length))" }
            if container == .oggOpus { return "Ogg Opus decoded on the device (\(length))" }
            return hadVideo ? "Soundtrack taken from the \(container.name) video (\(length))"
                            : "\(container.name) converted on the device (\(length))"
        }
    }

    /// Makes `source` readable by the pipeline. Writes `wav` when it has to; leaves `source` untouched.
    static func prepare(_ source: URL, wav: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Prepared {
        let container = AudioSniffer.sniff(fileAt: source)
        let name = source.lastPathComponent
        switch container {
        case .oggOpus:
            let seconds = try OggOpusDecoder.transcode(ogg: source, toWAV: wav)
            return Prepared(container: container, wav: wav, seconds: seconds, hadVideo: false)
        case .oggVorbis:
            throw AudioIntakeError.vorbis
        case .oggOther:
            throw AudioIntakeError.otherOgg
        case .ebml:
            throw AudioIntakeError.webm
        default:
            break
        }
        let asset = AVURLAsset(url: source)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        if videoTracks.isEmpty, let file = try? AVAudioFile(forReading: source), file.length > 0 {
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            return Prepared(container: container, wav: nil, seconds: seconds, hadVideo: false)
        }
        let seconds = try await extractSoundtrack(of: asset, name: name, toWAV: wav, progress: progress)
        return Prepared(container: container, wav: wav, seconds: seconds, hadVideo: !videoTracks.isEmpty)
    }

    /// The first audio track of `asset`, decoded and resampled by `AVAssetReader` to 16 kHz mono 16-bit PCM,
    /// written to `wav` a buffer at a time. Returns the seconds written.
    static func extractSoundtrack(of asset: AVURLAsset, name: String, toWAV wav: URL,
                                  progress: @escaping @Sendable (Double) -> Void) async throws -> Double {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AudioIntakeError.unreadable(name)
        }
        guard let track = tracks.first else {
            // No audio track: either a silent video, or not something AVFoundation can open at all.
            let playable = (try? await asset.load(.isReadable)) ?? false
            throw playable ? AudioIntakeError.noSoundtrack(name) : AudioIntakeError.unreadable(name)
        }
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: extractedRate, channels: 1, interleaved: true) else {
            throw AudioIntakeError.unreadable(name)
        }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw AudioIntakeError.unreadable(name) }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: extractedRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioIntakeError.unreadable(name) }
        reader.add(output)
        guard reader.startReading() else { throw AudioIntakeError.unreadable(name) }

        try? FileManager.default.removeItem(at: wav)
        var frames = 0
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            var lastReported = -1.0
            while let sample = output.copyNextSampleBuffer() {
                let count = CMSampleBufferGetNumSamples(sample)
                guard count > 0, let block = CMSampleBufferGetDataBuffer(sample),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let target = buffer.int16ChannelData?[0] else { continue }
                let length = min(CMBlockBufferGetDataLength(block), count * 2)
                guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: target) == kCMBlockBufferNoErr else {
                    throw AudioIntakeError.unreadable(name)
                }
                buffer.frameLength = AVAudioFrameCount(length / 2)
                try file.write(from: buffer)
                frames += length / 2
                if duration > 0 {
                    let done = min(1, Double(frames) / extractedRate / duration)
                    if done - lastReported >= 0.02 { lastReported = done; progress(done) }
                }
            }
            if reader.status == .failed { throw AudioIntakeError.unreadable(name) }
        } catch {
            reader.cancelReading()
            try? FileManager.default.removeItem(at: wav)
            throw (error as? AudioIntakeError) ?? AudioIntakeError.unreadable(name)
        }
        guard frames > 0 else {
            try? FileManager.default.removeItem(at: wav)
            throw AudioIntakeError.noSoundtrack(name)
        }
        return Double(frames) / extractedRate
    }
}
