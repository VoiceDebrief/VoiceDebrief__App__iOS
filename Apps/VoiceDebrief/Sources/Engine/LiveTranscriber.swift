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
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Never>?
    private var tapped = false
    /// Goes up on every stop, so a start that was still waiting (for a model download, say) when
    /// the recording stopped knows not to switch the microphone on afterwards.
    private var generation = 0

    /// Starts listening. `onText` gets the settled text so far and the part that may still change.
    func start(localeId: String, onText: @escaping @Sendable (String, String) -> Void) async throws {
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
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
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
