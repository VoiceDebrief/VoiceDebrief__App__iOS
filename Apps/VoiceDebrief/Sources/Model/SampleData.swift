#if DEBUG
import Foundation

/// Invented notes for the screenshots (issue 016). Nothing here was recorded, transcribed or
/// written by a model: every word was typed by hand, and each note says so in its own text, so a
/// screenshot cannot be mistaken for a real result. Reached only through `-VDSampleData`
/// (`LaunchOptions`), and not compiled into a release build.
enum SampleData {
    static let localeId = "en-GB"
    /// Where a real note says "Recorded here" or names the imported file.
    static let source = "Sample data, not a recording"

    enum Kind: String, CaseIterable, Sendable {
        case finished, transcriptOnly, interrupted, working, waiting, recording
    }

    /// One invented note: how long ago it was made, its run, and whether it is still marked as in progress.
    struct Sample: Sendable {
        let kind: Kind
        let secondsAgo: TimeInterval
        let run: DebriefRun
        let processing: Bool
        /// How long the silent recording written for this note is.
        var recordedSeconds: Double { run.audioSeconds ?? (kind == .interrupted ? 132 : 0.5) }
    }

    private static func lines(_ texts: [(Int, String)], last: Int) -> [TranscriptLine] {
        texts.enumerated().map { index, item in
            let end = index + 1 < texts.count ? texts[index + 1].0 : last
            return TranscriptLine(startMs: item.0 * 1000, endMs: end * 1000, text: item.1)
        }
    }

    /// A note taken all the way: a transcript and a debrief with the three headings.
    static var finished: Sample {
        var run = DebriefRun(source: source, localeId: localeId)
        run.audioSeconds = 49
        run.transcript = Transcript(localeId: localeId, lines: lines([
            (0, "Right, this is an invented sample note, made up so the screens have something to show."),
            (7, "Notes from the allotment committee on Thursday evening."),
            (12, "The shed roof leaks in two places and will not last another winter."),
            (19, "We agreed to replace the felt before the first frost, with a budget of two hundred and forty pounds."),
            (28, "Priya knows a roofer, so I will ask her for a quote by Monday."),
            (35, "Water butts: plot nine and plot twelve are sharing one until the spring."),
            (42, "Next meeting is the fourth of December at seven, in the village hall."),
        ], last: 49))
        run.debrief = """
            ## Key points
            - Invented sample note, made up for screenshots.
            - The shed roof leaks in two places and will not last another winter.
            - Agreed to replace the felt before the first frost, with a budget of £240.
            - Plots 9 and 12 share one water butt until the spring.
            - Next meeting: 4 December at 7, in the village hall.

            ## Actions
            - [me] Ask Priya for a roofer's quote by Monday.

            ## In one sentence
            Invented sample: the allotment shed gets new roof felt before the first frost, on a budget of £240.
            """
        run.sections = 1
        run.debriefHasAllSections = true
        run.modelContextSize = 4096
        run.steps = [
            StepRecord(name: "Transcript", outcome: .done, seconds: 1.4, note: "7 lines"),
            StepRecord(name: "Debrief", outcome: .done, seconds: 6.8, note: "One request"),
        ]
        return Sample(kind: .finished, secondsAgo: 25 * 60, run: run, processing: false)
    }

    /// A note too short to summarise: the transcript is the whole note, as the pipeline leaves it.
    static var transcriptOnly: Sample {
        var run = DebriefRun(source: source, localeId: localeId)
        run.audioSeconds = 6.5
        let spoken = lines([(0, "Invented sample: remind me to water the tomatoes on plot nine before Saturday.")], last: 6)
        run.transcript = Transcript(localeId: localeId, lines: spoken)
        run.steps = [
            StepRecord(name: "Transcript", outcome: .done, seconds: 0.6, note: "1 line"),
            StepRecord(name: "Debrief", outcome: .degraded, seconds: 0,
                       note: "Too short to summarise (\(DebriefPrompt.wordCount(spoken)) words): the transcript is the whole note."),
        ]
        return Sample(kind: .transcriptOnly, secondsAgo: 2 * 3600, run: run, processing: false)
    }

    /// A note that was cut off: still marked as in progress, with nothing made from it yet.
    static var interrupted: Sample {
        let run = DebriefRun(source: source, localeId: localeId)
        return Sample(kind: .interrupted, secondsAgo: 26 * 3600, run: run, processing: true)
    }

    /// A note whose transcript is there and whose debrief is being written now.
    static var working: Sample {
        var run = DebriefRun(source: source, localeId: localeId)
        run.audioSeconds = 31
        run.transcript = Transcript(localeId: localeId, lines: lines([
            (0, "Invented sample, still being written up when this picture was taken."),
            (6, "Seed order for the spring: broad beans, two kinds of beetroot and the purple carrots again."),
            (15, "Ask at the next meeting whether anyone wants to share a delivery of compost."),
            (23, "And the gate latch on the lane side needs oiling before it seizes."),
        ], last: 31))
        run.steps = [
            StepRecord(name: "Transcript", outcome: .done, seconds: 1.1, note: "4 lines"),
            StepRecord(name: "Debrief", outcome: .running, seconds: 0, note: ""),
        ]
        return Sample(kind: .working, secondsAgo: 60, run: run, processing: true)
    }

    /// A note recorded while the one before it was still being written up: it waits its turn.
    static var waiting: Sample {
        var run = DebriefRun(source: source, localeId: localeId)
        run.audioSeconds = 12
        return Sample(kind: .waiting, secondsAgo: 15, run: run, processing: true)
    }

    /// The note that exists from the moment a recording starts.
    static var recording: Sample {
        Sample(kind: .recording, secondsAgo: recordingSeconds, run: DebriefRun(source: source, localeId: localeId), processing: true)
    }

    static let recordingSeconds: TimeInterval = 83

    /// The words on the record screen while recording: settled, and still changing.
    static let liveSettled = "This is an invented sample of the live text. The words appear here as they are spoken, "
    static let liveVolatile = "and the last few can still change"

    /// Loudness for the level bars, 0 to 1: a fixed shape, so two runs give the same picture.
    /// As many as the level display holds (`DebriefSession.levelCount`; a test keeps the two equal).
    static let levelCount = 40
    static let levels: [Double] = (0..<levelCount).map { index in
        let x = Double(index)
        return min(1, max(0.05, 0.45 + 0.35 * sin(x * 0.55) + 0.2 * sin(x * 1.7 + 1)))
    }

    /// The notes a screen is shown over, oldest first. The empty set has none.
    static func notes(for screen: LaunchScreen, set: SampleSet) -> [Sample] {
        guard set == .full else { return [] }
        var out = [interrupted, transcriptOnly, finished]
        switch screen {
        case .library, .recordWorking, .noteWorking, .noteQueued: out += [working, waiting]
        case .recordRecording: out.append(recording)
        default: break
        }
        return out
    }

    /// The note a note screen opens.
    static func kind(for screen: LaunchScreen) -> Kind? {
        switch screen {
        case .noteFinished: return .finished
        case .noteTranscript: return .transcriptOnly
        case .noteInterrupted: return .interrupted
        case .noteWorking, .noteQueued: return .working
        default: return nil
        }
    }

    static let vaultName = "Sample vault (invented)"
    /// Somebody a note can be sent to. Her lane is invented: nothing is ever sent to it.
    static let recipientName = "Maria (invented)"
    static let serverName = "Sample server (invented)"
    /// A name that can never resolve (RFC 6761), in case anything ever tried.
    static let serverAddress = "https://sample-server.invalid"

    /// Half a second of silence, for where only the form matters.
    static var silentWAV: Data { silence(seconds: 0.5) }

    /// Silence as a 16 kHz mono WAV of the given length, so a sample note has an audio file as a real
    /// one does and a player shows the length the note claims.
    static func silence(seconds: Double) -> Data {
        let samples = max(1, Int(seconds * 16_000))
        let dataBytes = UInt32(samples * 2)
        var out = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        out.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataBytes)
        out.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(16_000)
        append32(32_000)
        append16(2)
        append16(16)
        out.append(contentsOf: Array("data".utf8))
        append32(dataBytes)
        out.append(Data(count: Int(dataBytes)))
        return out
    }
}
#endif
