import Foundation
import Observation

/// One voice note at a time, taken from audio to transcript to debrief. Holds the state the
/// screens show. Nothing is saved in this build: closing the app loses the run.
@MainActor
@Observable
final class DebriefSession {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case working(String)
        case done
        case failed(String)
    }

    /// Sending the last note to the developer's lane: nothing, in progress, done, or why it failed.
    enum Sharing: Equatable {
        case idle
        case sending(Int, Int)
        case sent(Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var run: DebriefRun?
    private(set) var sharing: Sharing = .idle
    /// The audio of the last run, kept only so that it can be sent if the user asks. Deleted when
    /// the next run starts or the result is cleared.
    private var lastAudio: URL?
    private let recorder = VoiceRecorder()

    /// While recording: the words heard so far (settled, and still changing), recent loudness for the
    /// level display, and why there is no live text if there is none.
    private(set) var liveSettled = ""
    private(set) var liveVolatile = ""
    private(set) var liveNote = ""
    private(set) var levels: [Double] = []
    static let levelCount = 40
    private let live = LiveTranscriber()
    private var meter: Task<Void, Never>?

    var canShareAudio: Bool { lastAudio != nil && run?.transcript != nil }

    var isBusy: Bool {
        switch phase {
        case .recording, .working: return true
        default: return false
        }
    }

    // MARK: Recording

    func startRecording(localeId: String) async {
        do {
            try await recorder.start()
            forgetAudio()
            run = nil
            liveSettled = ""
            liveVolatile = ""
            liveNote = ""
            levels = []
            phase = .recording(since: Date())
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                self?.pushLevel()
            }
        }
        // The live text is a preview. If it cannot start, the recording goes on without it.
        do {
            try await live.start(localeId: localeId) { settled, volatile in
                Task { @MainActor [weak self] in
                    self?.liveSettled = settled
                    self?.liveVolatile = volatile
                }
            }
        } catch {
            liveNote = "No live text: \(error.localizedDescription). The recording is still running."
        }
    }

    private func pushLevel() {
        guard case .recording = phase else { return }
        levels.append(recorder.level())
        if levels.count > Self.levelCount { levels.removeFirst(levels.count - Self.levelCount) }
    }

    func stopRecording(localeId: String) async {
        meter?.cancel()
        meter = nil
        await live.stop()
        guard let url = recorder.stop() else {
            phase = .failed("Nothing was recorded.")
            return
        }
        await process(url: url, source: "Recorded here", localeId: localeId)
    }

    // MARK: Importing

    /// A file picked in the Files sheet. It is copied first: the picked URL is only readable for a moment.
    func importFile(_ picked: URL, localeId: String) async {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(Int(Date().timeIntervalSince1970))-\(picked.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: picked, to: copy)
        } catch {
            phase = .failed("That file could not be opened.")
            return
        }
        await process(url: copy, source: picked.lastPathComponent, localeId: localeId)
    }

    // MARK: The pipeline

    private func forgetAudio() {
        if let lastAudio { try? FileManager.default.removeItem(at: lastAudio) }
        lastAudio = nil
        sharing = .idle
    }

    private func process(url: URL, source: String, localeId: String) async {
        forgetAudio()
        lastAudio = url
        var current = DebriefRun(source: source, localeId: localeId)
        current.audioSeconds = SpeechFileTranscriber.audioSeconds(url: url)
        run = current

        // 1. Transcript
        phase = .working("Transcribing")
        var started = Date()
        current.steps.append(StepRecord(name: "Transcript", outcome: .running, seconds: 0, note: ""))
        run = current
        do {
            let transcript = try await SpeechFileTranscriber.transcribe(url: url, localeId: localeId) { status in
                Task { @MainActor [weak self] in self?.setWorking(status) }
            }
            current.transcript = transcript
            let note = transcript.isEmpty ? "No speech was found." : "\(transcript.lines.count) lines"
            finish(&current, outcome: transcript.isEmpty ? .degraded : .done, since: started, note: note)
        } catch {
            finish(&current, outcome: .failed, since: started, note: error.localizedDescription)
            run = current
            phase = .failed(error.localizedDescription)
            return
        }
        run = current
        guard let transcript = current.transcript, !transcript.isEmpty else {
            phase = .done
            return
        }

        // 2. Debrief. A failure here degrades: the transcript stands on its own.
        phase = .working("Writing the debrief")
        started = Date()
        current.steps.append(StepRecord(name: "Debrief", outcome: .running, seconds: 0, note: ""))
        run = current
        let words = DebriefPrompt.wordCount(transcript.lines)
        if words < DebriefPrompt.minimumWords {
            finish(&current, outcome: .degraded, since: started,
                   note: "Too short to summarise (\(words) words): the transcript is the whole note.")
            run = current
            phase = .done
            return
        }
        guard let contextSize = OnDeviceModel.contextSize else {
            finish(&current, outcome: .degraded, since: started, note: OnDeviceModel.status.text)
            run = current
            phase = .done
            return
        }
        current.modelContextSize = contextSize
        do {
            let voice = DebriefPrompt.voice(forLocale: transcript.localeId)
            let budget = Chunker.characterBudget(contextSize: contextSize)
            let chunks = Chunker.chunks(transcript.lines, budget: budget)
            current.sections = chunks.count
            let debrief: String
            if chunks.count <= 1 {
                debrief = try await OnDeviceModel.respond(to: DebriefPrompt.debrief(transcript: transcript.timedText, voice: voice))
            } else {
                var notes: [String] = []
                for (index, chunk) in chunks.enumerated() {
                    setWorking("Reading part \(index + 1) of \(chunks.count)")
                    let prompt = DebriefPrompt.notes(section: index + 1, of: chunks.count,
                                                     transcript: Transcript.timedText(chunk), voice: voice)
                    let part = try await OnDeviceModel.respond(to: prompt)
                    notes.append("Part \(index + 1):\n" + part)
                }
                setWorking("Writing the debrief")
                debrief = try await OnDeviceModel.respond(to: DebriefPrompt.merge(notes: notes.joined(separator: "\n\n"), voice: voice))
            }
            current.debrief = debrief
            current.debriefHasAllSections = DebriefPrompt.hasAllSections(debrief)
            let note = chunks.count > 1 ? "Read in \(chunks.count) parts" : "One request"
            finish(&current, outcome: current.debriefHasAllSections ? .done : .degraded, since: started,
                   note: current.debriefHasAllSections ? note : note + "; the model did not keep the three headings")
        } catch {
            finish(&current, outcome: .degraded, since: started, note: error.localizedDescription)
        }
        run = current
        phase = .done
    }

    private func setWorking(_ text: String) {
        if case .working = phase { phase = .working(text) }
    }

    private func finish(_ run: inout DebriefRun, outcome: StepRecord.Outcome, since: Date, note: String) {
        guard !run.steps.isEmpty else { return }
        let last = run.steps.count - 1
        run.steps[last].outcome = outcome
        run.steps[last].seconds = Date().timeIntervalSince(since)
        run.steps[last].note = note
    }

    func reset() {
        guard !isBusy else { return }
        forgetAudio()
        run = nil
        phase = .idle
    }

    // MARK: Sending to the developer

    /// Sends the last note's audio, transcript and debrief to the developer's lane, encrypted to the
    /// developer's key. Only ever called from the button that says so.
    func shareWithDeveloper(lane: DeveloperLane) async {
        guard let url = lastAudio, let run else { return }
        if case .sending = sharing { return }
        sharing = .sending(0, 0)
        do {
            let audio = try Data(contentsOf: url)
            let noteId = UUID().uuidString.lowercased()
            let messages = try DeveloperLane.messages(audio: audio, audioName: url.lastPathComponent, run: run,
                                                      noteId: noteId, app: AppInfo.versionLine(), at: Date())
            try await lane.send(messages) { done, total in
                Task { @MainActor [weak self] in self?.sharing = .sending(done, total) }
            }
            sharing = .sent(messages.count)
        } catch {
            sharing = .failed(error.localizedDescription)
        }
    }
}
