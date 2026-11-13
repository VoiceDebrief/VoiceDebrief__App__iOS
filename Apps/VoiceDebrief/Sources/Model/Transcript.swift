import Foundation

/// One phrase of a transcript, with where it sits in the audio.
struct TranscriptLine: Codable, Equatable, Sendable, Identifiable {
    let startMs: Int
    let endMs: Int
    let text: String

    var id: Int { startMs }
}

/// What the speech model heard, in order.
struct Transcript: Codable, Equatable, Sendable {
    let localeId: String
    let lines: [TranscriptLine]

    var isEmpty: Bool { lines.isEmpty }
    var durationMs: Int { lines.last?.endMs ?? 0 }
    var characterCount: Int { lines.reduce(0) { $0 + $1.text.count } }

    /// The transcript as the model reads it: "[mm:ss] text", one phrase a line.
    var timedText: String { Transcript.timedText(lines) }

    static func timedText(_ lines: [TranscriptLine]) -> String {
        lines.map { "[\(Timecode.format(ms: $0.startMs))] \($0.text)" }.joined(separator: "\n")
    }
}

enum Timecode {
    /// "mm:ss", or "h:mm:ss" from an hour up. Negative values read as zero.
    static func format(ms: Int) -> String {
        let total = max(0, ms) / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let mm = m < 10 ? "0\(m)" : "\(m)"
        let ss = s < 10 ? "0\(s)" : "\(s)"
        return h > 0 ? "\(h):\(mm):\(ss)" : "\(mm):\(ss)"
    }

    /// "1.2 s" or "3 min 05 s", for how long a step took.
    static func duration(seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let whole = Int(seconds.rounded())
        let s = whole % 60
        return "\(whole / 60) min \(s < 10 ? "0\(s)" : "\(s)") s"
    }
}
