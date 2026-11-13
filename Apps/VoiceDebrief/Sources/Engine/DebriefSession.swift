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

    private(set) var phase: Phase = .idle
    private(set) var run: DebriefRun?
    private let recorder = VoiceRecorder()

    var isBusy: Bool {
        switch phase {
        case .recording, .working: return true
        default: return false
        }
    }

    // MARK: Recording

    func startRecording() async {
        do {
            try await recorder.start()
            run = nil
            phase = .recording(since: Date())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopRecording(localeId: String) async {
        guard let url = recorder.stop() else {
            phase = .failed("Nothing was recorded.")
            return
        }
        await process(url: url, source: "Recorded here", localeId: localeId)
        try? FileManager.default.removeItem(at: url)
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
        try? FileManager.default.removeItem(at: copy)
    }

    // MARK: The pipeline

    private func process(url: URL, source: String, localeId: String) async {
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
        run = nil
        phase = .idle
    }
}
