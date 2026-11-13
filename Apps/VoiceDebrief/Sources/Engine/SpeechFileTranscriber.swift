import AVFoundation
import CoreMedia
import Foundation
import Speech

enum TranscribeError: LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple's speech model is not available on this device."
        case .unsupportedLocale(let id):
            return "Apple's speech model does not support \(id) on this device."
        case .unreadable(let name):
            return "This audio could not be read (\(name)). WhatsApp's Ogg Opus files need a decoder this build does not have yet; .m4a, .mp3 and .wav work."
        }
    }
}

/// A recorded or imported audio file to a transcript, with Apple's SpeechAnalyzer, on the device.
enum SpeechFileTranscriber {
    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    /// Every locale the speech model can transcribe, as BCP 47 identifiers, sorted.
    static func supportedLocaleIds() async -> [String] {
        await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
    }

    /// The locales whose model is already on the device.
    static func installedLocaleIds() async -> [String] {
        await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted()
    }

    /// The supported locale closest to the device's own, if there is one.
    static func defaultLocaleId() async -> String? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)?.identifier(.bcp47)
    }

    static func transcribe(url: URL, localeId: String,
                           onStatus: @escaping @Sendable (String) -> Void) async throws -> Transcript {
        guard SpeechTranscriber.isAvailable else { throw TranscribeError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeId)) else {
            throw TranscribeError.unsupportedLocale(localeId)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus("Downloading Apple's speech model for \(localeId)")
            try await request.downloadAndInstall()
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TranscribeError.unreadable(url.lastPathComponent)
        }

        onStatus("Transcribing")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> [TranscriptLine] in
            var lines: [TranscriptLine] = []
            for try await result in transcriber.results {
                guard result.isFinal else { continue }
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                lines.append(TranscriptLine(startMs: milliseconds(result.range.start),
                                            endMs: milliseconds(result.range.end),
                                            text: text))
            }
            return lines
        }

        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }
        let lines = try await collector.value
        return Transcript(localeId: locale.identifier(.bcp47), lines: lines)
    }

    /// The length of an audio file in seconds, if it can be read.
    static func audioSeconds(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }

    static func milliseconds(_ time: CMTime) -> Int {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }
}
