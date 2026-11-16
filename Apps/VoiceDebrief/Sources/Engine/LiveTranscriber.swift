import AVFoundation
import Foundation
import Speech

/// The words as they are spoken, shown while a note is being recorded. A preview only: when the
/// recording stops, the transcript is made again from the recorded file, which is what is kept.
/// If anything here fails, the recording carries on without a preview.
final class LiveTranscriber: @unchecked Sendable {
    enum Failure: LocalizedError {
        case unsupportedLocale
        case noFormat
        case noInput

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: return "the speech model does not support this language"
            case .noFormat: return "the speech model gave no audio format"
            case .noInput: return "there is no microphone input"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let converter = BufferConverter()
    /// What the engine itself hears, written to a file while a note records: the recording's safety net.
    let backup = TapBackup()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Never>?
    private var tapped = false
    /// Goes up on every stop, so a start that was still waiting (for a model download, say) when
    /// the recording stopped knows not to switch the microphone on afterwards.
    private var generation = 0

    /// Starts listening. `onText` gets the settled text so far and the part that may still change.
    func start(localeId: String, backupTo backupURL: URL? = nil, onText: @escaping @Sendable (String, String) -> Void) async throws {
        let mine = generation
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeId)) else {
            throw Failure.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noFormat
        }

        guard mine == generation else { return }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.continuation = continuation

        results = Task {
            var settled = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        settled += text
                        onText(settled, "")
                    } else {
                        onText(settled, text)
                    }
                }
            } catch {
                // A preview that stops is not an error worth showing: the recording goes on.
            }
        }

        try await analyzer.start(inputSequence: stream)
        guard mine == generation else {
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            return
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Failure.noInput }
        let converter = self.converter
        let backup = self.backup
        if let backupURL { backup.open(backupURL, format: inputFormat) }
        // installTap raises an Objective-C exception, which Swift cannot catch, if a tap is already on the bus
        // or the format given does not match the hardware's; it crashed build 0.1.91 on the owner's iPhone
        // (14 November 2026). So: take off any tap left from before, and let the node use its own format
        // (nil); each buffer says its format and the converter follows it.
        input.removeTap(onBus: 0)
        tapped = false
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            backup.write(buffer)
            guard let converted = converter.convert(buffer, to: format) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        tapped = true
        engine.prepare()
        try engine.start()
    }

    func stop() async {
        generation += 1
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        if engine.isRunning { engine.stop() }
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        results?.cancel()
        results = nil
    }
}

/// The live engine's own audio, written to a file beside the note while it records. Several notes from the
/// owner's iPhone and iPad (0.1.72, 0.1.120, twice on 0.1.123) were pure digital silence: the recorder wrote
/// zeros while the live preview's engine held the input. The engine's buffers are the sound it did hear, so
/// they are kept, and when the recorder's file turns out silent the note is made from this instead (never
/// lose a recording). Stays open across a pause, so the take resumes in the same file; `finish` closes it.
final class TapBackup: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var format: AVAudioFormat?
    private var loudest: Float = 0
    private(set) var url: URL?

    /// Opens the file for a new take, or keeps the one already open for this take (after a pause). The file
    /// is made on the first buffer, in that buffer's own format, so it always matches what the engine gives.
    func open(_ url: URL, format: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        if self.url == url { return }
        file = nil
        self.format = nil
        self.url = url
        loudest = 0
    }

    /// Called on the audio thread for each buffer the engine hears.
    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let url else { return }
        if file == nil {
            let f = buffer.format
            // 16-bit on disk (about 5.7 MB a minute at 48 kHz), the engine's own format in memory.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: f.sampleRate,
                AVNumberOfChannelsKey: f.channelCount, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            ]
            file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: f.commonFormat, interleaved: f.isInterleaved)
            format = f
        }
        guard let file, buffer.format == format else { return }
        try? file.write(from: buffer)
        if let channel = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
            loudest = max(loudest, peak)
        }
    }

    /// The loudest sample heard so far, from 0 to 1 (0.001 is about -60 dB, a very quiet room).
    var peak: Float { lock.lock(); defer { lock.unlock() }; return loudest }

    /// Closes the file; returns where it is and the loudest sample, or nil if nothing was written.
    func finish() -> (url: URL, peak: Float)? {
        lock.lock(); defer { lock.unlock() }
        defer { file = nil; format = nil; url = nil; loudest = 0 }
        guard let url, file != nil else { return nil }
        return (url, loudest)
    }

    /// Writes the backup as the note's audio file (16-bit PCM at the backup's own rate, its channels).
    static func replace(_ target: URL, with backup: URL) throws {
        let source = try AVAudioFile(forReading: backup)
        let processing = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: processing.sampleRate,
            AVNumberOfChannelsKey: processing.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let temporary = target.deletingLastPathComponent().appending(path: "audio-rescued.wav")
        try? FileManager.default.removeItem(at: temporary)
        do {
            let out = try AVAudioFile(forWriting: temporary, settings: settings,
                                      commonFormat: processing.commonFormat, interleaved: processing.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 16_384) else { return }
            while source.framePosition < source.length {
                try source.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try out.write(from: buffer)
            }
        }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
    }
}

/// Converts the microphone's buffers to the format the speech model asks for.
final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter, buffer.format.sampleRate > 0 else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        nonisolated(unsafe) var consumed = false
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
