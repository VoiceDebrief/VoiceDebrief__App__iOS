import AVFoundation
import Foundation

enum RecorderError: LocalizedError {
    case denied
    case failed

    var errorDescription: String? {
        switch self {
        case .denied: return "The microphone is not allowed. Allow it for VoiceDebrief in Settings."
        case .failed: return "Recording could not start."
        }
    }
}

/// Records a voice note to a temporary .m4a file. The file is kept only for this run.
@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var url: URL?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.denied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-note-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let made = try AVAudioRecorder(url: file, settings: settings)
        made.isMeteringEnabled = true
        guard made.record() else { throw RecorderError.failed }
        recorder = made
        url = file
    }

    /// How loud the microphone is now, from 0 (silence) to 1. Zero when not recording.
    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return VoiceRecorder.level(decibels: Double(recorder.averagePower(forChannel: 0)))
    }

    /// The meter's decibels (0 is full scale, about -50 is a quiet room) as 0 to 1.
    nonisolated static func level(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels + 50) / 50))
    }

    /// Stops and returns the recorded file, if there is one.
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { url = nil }
        return url
    }
}
