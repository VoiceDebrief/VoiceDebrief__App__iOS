import AVFoundation
import Foundation

/// Decodes the Opus packets of an Ogg Opus file (`OggOpus`) with Apple's own Opus decoder, through
/// `AVAudioConverter` and `kAudioFormatOpus`, to 32-bit float PCM at 48 kHz. No third-party code.
///
/// The decoder is handed one packet at a time. Opus packets may differ in length (2.5 to 120 ms); the
/// converter is told a fixed number of frames per packet, so a run of packets of one length is decoded by
/// one converter and a change of length starts another. A voice note from WhatsApp is one run.
enum OggOpusDecoder {
    /// The PCM format the decoder produces.
    static func pcmFormat(channels: Int) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(OggOpusStream.sampleRate),
                      channels: AVAudioChannelCount(channels), interleaved: false)
    }

    /// Decodes the whole stream, handing the PCM to `sink` in pieces, with the pre-skip removed from the start,
    /// the padding removed from the end and the header's output gain applied. Returns the frames handed on.
    @discardableResult
    static func decode(_ stream: OggOpusStream, sink: (AVAudioPCMBuffer) throws -> Void) throws -> Int {
        let channels = stream.head.channels
        guard let output = pcmFormat(channels: channels) else { throw OggOpusError.decoderUnavailable }
        var toSkip = stream.head.preSkip
        var toKeep = stream.sampleCount
        var handedOn = 0
        let gain = stream.head.gainFactor

        func take(_ buffer: AVAudioPCMBuffer) throws {
            var start = 0
            var length = Int(buffer.frameLength)
            if toSkip > 0 {
                let skipped = min(toSkip, length)
                toSkip -= skipped
                start += skipped
                length -= skipped
            }
            length = min(length, toKeep)
            guard length > 0, let piece = slice(buffer, from: start, length: length, gain: gain) else { return }
            toKeep -= length
            handedOn += length
            try sink(piece)
        }

        // Runs of packets with the same length.
        var runStart = 0
        while runStart < stream.packets.count, toKeep > 0 {
            let frames = OggOpus.samples(inPacket: stream.packets[runStart]) ?? 960
            var runEnd = runStart + 1
            while runEnd < stream.packets.count, OggOpus.samples(inPacket: stream.packets[runEnd]) == frames { runEnd += 1 }
            try decodeRun(stream.packets[runStart ..< runEnd], framesPerPacket: frames, channels: channels,
                          output: output, firstIndex: runStart, sink: take)
            runStart = runEnd
        }
        return handedOn
    }

    private static func decodeRun(_ packets: ArraySlice<Data>, framesPerPacket: Int, channels: Int,
                                  output: AVAudioFormat, firstIndex: Int,
                                  sink: (AVAudioPCMBuffer) throws -> Void) throws {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(OggOpusStream.sampleRate), mFormatID: kAudioFormatOpus, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(framesPerPacket), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw OggOpusError.decoderUnavailable
        }
        // The pre-skip is removed by `decode` itself, from the header; the converter must not trim as well.
        converter.primeMethod = .none

        let maximum = packets.map(\.count).max() ?? 0
        guard maximum > 0 else { throw OggOpusError.badPacket(index: firstIndex + 1) }
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: maximum)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(framesPerPacket * 50)) else {
            throw OggOpusError.decodeFailed("no buffer")
        }
        var next = packets.startIndex
        var finished = false
        while !finished {
            pcm.frameLength = 0
            var problem: NSError?
            let status = converter.convert(to: pcm, error: &problem) { _, outStatus in
                guard next < packets.endIndex else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                let packet = packets[next]
                next += 1
                packet.withUnsafeBytes { raw in
                    compressed.data.copyMemory(from: raw.baseAddress!, byteCount: packet.count)
                }
                compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(
                    mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
                compressed.packetCount = 1
                compressed.byteLength = UInt32(packet.count)
                outStatus.pointee = .haveData
                return compressed
            }
            switch status {
            case .haveData:
                break
            case .endOfStream, .inputRanDry:
                finished = true
            case .error:
                let at = firstIndex + (next - packets.startIndex)
                throw OggOpusError.decodeFailed("packet \(at): \(problem?.localizedDescription ?? "the decoder refused it")")
            @unknown default:
                finished = true
            }
            if pcm.frameLength > 0 { try sink(pcm) }
        }
    }

    /// A copy of part of a buffer, with a gain applied.
    static func slice(_ buffer: AVAudioPCMBuffer, from start: Int, length: Int, gain: Float = 1) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length)),
              let from = buffer.floatChannelData, let to = copy.floatChannelData else { return nil }
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let source = from[channel] + start
            let target = to[channel]
            if gain == 1 {
                target.update(from: source, count: length)
            } else {
                for i in 0 ..< length { target[i] = source[i] * gain }
            }
        }
        copy.frameLength = AVAudioFrameCount(length)
        return copy
    }

    // MARK: To a file the pipeline reads

    /// Reads an Ogg Opus file and writes it out as 16-bit WAV at 48 kHz, which `AVAudioFile`, Apple's speech
    /// model and the note's compressor all read. Returns the length in seconds. Throws a plain message if the
    /// file is not Ogg Opus or is damaged; nothing is left at `wav` then.
    @discardableResult
    static func transcode(ogg: URL, toWAV wav: URL) throws -> Double {
        let data: Data
        do { data = try Data(contentsOf: ogg) } catch { throw OggOpusError.decodeFailed("the file could not be read") }
        let stream = try OggOpus.parse(data)
        guard let format = pcmFormat(channels: stream.head.channels) else { throw OggOpusError.decoderUnavailable }
        try? FileManager.default.removeItem(at: wav)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: wav, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let frames = try decode(stream) { try file.write(from: $0) }
            guard frames > 0 else { throw OggOpusError.noAudio }
            return Double(frames) / format.sampleRate
        } catch let error as OggOpusError {
            try? FileManager.default.removeItem(at: wav)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: wav)
            throw OggOpusError.decodeFailed(error.localizedDescription)
        }
    }

    /// The length of an Ogg Opus file in seconds, from its pages alone, without decoding.
    static func seconds(ofFileAt url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url), let stream = try? OggOpus.parse(data) else { return nil }
        return stream.seconds
    }
}
