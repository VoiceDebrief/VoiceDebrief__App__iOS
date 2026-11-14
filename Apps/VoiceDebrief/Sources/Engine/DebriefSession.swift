import AVFoundation
import Foundation
import Observation

/// One voice note at a time, taken from audio to transcript to debrief. A note is written to the
/// library the moment its recording stops, and updated after every step, so nothing here is the
/// only copy of anything.
@MainActor
@Observable
final class DebriefSession {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case working(String)
        case failed(String)
    }

    /// Sending the last note to the developer's lane: nothing, in progress, done, or why it failed.
    enum Sharing: Equatable {
        case idle
        case sending(Int, Int)
        case sent(Int)
        case failed(String)
    }

    let store: NoteStore
    /// Called once a note is finished and its audio is in its final form: the moment to save it elsewhere.
    var onNoteReady: ((String) -> Void)?
    /// What the record screen shows. Recording and processing are kept apart, so that a recording can
    /// start while the last note is still being written up (review round 1, issue 030); a recording in
    /// progress is what the screen shows first.
    var phase: Phase {
        if let since = recordingSince { return .recording(since: since) }
        if let working { return .working(working) }
        if let failure { return .failed(failure) }
        return .idle
    }
    private var recordingSince: Date?
    /// What the pipeline is doing to `currentNoteId` right now, in words; nil when it is idle.
    private var working: String?
    private var failure: String?
    /// Notes waiting their turn for the pipeline, oldest first.
    private(set) var waiting: [String] = []
    /// The note being processed now, or the last one that was.
    private(set) var currentNoteId: String?
    private(set) var sharing: Sharing = .idle
    /// The note the `sharing` state is about.
    private(set) var sharingNoteId: String?
    private let recorder = VoiceRecorder()

    /// The note being recorded now, and the language chosen for it.
    private var recordingNoteId: String?
    private var recordingLocaleId = ""
    /// Something the record screen should say once, such as a recording that was cut short.
    private(set) var notice: String?

    init(store: NoteStore) {
        self.store = store
        // A phone call, or another app taking the microphone, ends the recording. Keep what there is.
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in await self?.recordingWasInterrupted() }
        }
    }

    private func recordingWasInterrupted() async {
        guard recordingSince != nil else { return }
        _ = await stopRecording()
        notice = "The recording was interrupted (a call, or another app took the microphone). What was recorded is kept and is being transcribed."
    }

    func clearNotice() { notice = nil }

    /// The run of the current note, for the diagnostics report.
    var run: DebriefRun? { currentNoteId.flatMap { store.note($0)?.run } }

    /// What is being done to a note right now, in words, if it is the one being processed.
    /// The note whose recording is being made right now, if any.
    var recordingNote: String? { recordingNoteId }

    func workingText(for noteId: String) -> String? {
        if noteId == currentNoteId, let working { return working }
        if waiting.contains(noteId) { return "Waiting its turn" }
        return nil
    }

    /// True while the pipeline is writing up a note: the record control stays live all the same.
    var isProcessing: Bool { working != nil }

    /// While recording: the words heard so far (settled, and still changing), recent loudness for the
    /// level display, and why there is no live text if there is none.
    private(set) var liveSettled = ""
    private(set) var liveVolatile = ""
    private(set) var liveNote = ""
    private(set) var levels: [Double] = []
    static let levelCount = 40
    private let live = LiveTranscriber()
    private var meter: Task<Void, Never>?

    /// Recording, or writing a note up: the language cannot be changed then.
    var isBusy: Bool { recordingSince != nil || working != nil }

    // MARK: Recording

    func startRecording(localeId: String) async {
        notice = nil
        // The note and its file exist before recording starts: see NoteStore.begin.
        guard let (note, audio) = store.begin(source: "Recorded here", localeId: localeId) else {
            failure = store.problem ?? "A place for the recording could not be made."
            return
        }
        do {
            try await recorder.start(writingTo: audio)
            recordingNoteId = note.id
            recordingLocaleId = localeId
            liveSettled = ""
            liveVolatile = ""
            liveNote = ""
            levels = []
            failure = nil
            recordingSince = Date()
        } catch {
            store.delete(note.id)
            failure = error.localizedDescription
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
        guard recordingSince != nil else { return }
        levels.append(recorder.level())
        if levels.count > Self.levelCount { levels.removeFirst(levels.count - Self.levelCount) }
    }

    /// Stops the recording and starts the transcript and debrief. The note has been in the library
    /// since the recording began. Returns its id at once, so the screen can show it while it fills in.
    func stopRecording() async -> String? {
        meter?.cancel()
        meter = nil
        await live.stop()
        recorder.stop()
        recordingSince = nil
        guard let id = recordingNoteId else {
            failure = "Nothing was recorded."
            return nil
        }
        recordingNoteId = nil
        guard store.audioURL(for: id) != nil else {
            store.delete(id)
            failure = "Nothing was recorded."
            return nil
        }
        enqueue(id)
        return id
    }

    /// Throws the recording in progress away: the audio and its note. The one way a recording is
    /// lost on purpose, so the screen asks twice before calling it.
    func discardRecording() async {
        meter?.cancel()
        meter = nil
        await live.stop()
        recorder.stop()
        if let id = recordingNoteId { store.delete(id) }
        recordingNoteId = nil
        recordingSince = nil
    }

    // MARK: Importing

    /// A file picked in the Files sheet. It is copied first: the picked URL is only readable for a moment.
    func importFile(_ picked: URL, localeId: String) -> String? {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(Int(Date().timeIntervalSince1970)).\(picked.pathExtension)")
        do {
            try FileManager.default.copyItem(at: picked, to: copy)
        } catch {
            failure = "That file could not be opened."
            return nil
        }
        let id = begin(audioAt: copy, source: picked.lastPathComponent, localeId: localeId)
        if id != nil { CreditLedger.shared.charge(.importFile, noteId: id) }
        return id
    }

    /// Keeps the audio as a new note, then processes it without making the caller wait.
    private func begin(audioAt url: URL, source: String, localeId: String) -> String? {
        guard let note = store.create(audioAt: url, source: source, localeId: localeId) else {
            failure = store.problem ?? "The recording could not be kept."
            return nil
        }
        enqueue(note.id)
        return note.id
    }

    /// Transcribes and debriefs a note again from its kept audio: for a note that was interrupted,
    /// or after changing the language or switching Apple Intelligence on.
    func reprocess(_ noteId: String, localeId: String) {
        guard noteId != recordingNoteId, !isBusyWith(noteId), var run = store.note(noteId)?.run else { return }
        run = DebriefRun(source: run.source, localeId: localeId)
        store.update(noteId, run: run, processing: true)
        enqueue(noteId)
    }

    /// Puts a note in line for the pipeline, and starts it if nothing is being written up.
    private func enqueue(_ noteId: String) {
        guard !waiting.contains(noteId), !(noteId == currentNoteId && working != nil) else { return }
        waiting.append(noteId)
        startNext()
    }

    private func startNext() {
        guard working == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        currentNoteId = next
        working = "Transcribing"
        Task { await process(noteId: next) }
    }

    /// The pipeline has finished with the current note: take the next one waiting.
    private func doneProcessing() {
        working = nil
        startNext()
    }

    // MARK: The pipeline

    private func process(noteId: String) async {
        guard let note = store.note(noteId), let url = store.audioURL(for: noteId) else {
            doneProcessing()
            return
        }
        let localeId = note.run.localeId
        var current = DebriefRun(source: note.run.source, localeId: localeId)
        current.audioSeconds = SpeechFileTranscriber.audioSeconds(url: url)
        /// Writes the run to the library; `finished` ends the note's processing and frees the recorder.
        func publish(finished: Bool = false) {
            store.update(noteId, run: current, processing: !finished)
            if finished {
                compressAudio(of: noteId)
                doneProcessing()
            }
        }
        publish()

        // 1. Transcript
        working = "Transcribing"
        var started = Date()
        current.steps.append(StepRecord(name: "Transcript", outcome: .running, seconds: 0, note: ""))
        publish()
        do {
            let transcript = try await SpeechFileTranscriber.transcribe(url: url, localeId: localeId) { status in
                Task { @MainActor [weak self] in self?.setWorking(status) }
            }
            current.transcript = transcript
            let note = transcript.isEmpty ? "No speech was found." : (transcript.lines.count == 1 ? "1 line" : "\(transcript.lines.count) lines")
            finish(&current, outcome: transcript.isEmpty ? .degraded : .done, since: started, note: note)
        } catch {
            finish(&current, outcome: .failed, since: started, note: error.localizedDescription)
            publish(finished: true)
            return
        }
        guard let transcript = current.transcript, !transcript.isEmpty else {
            publish(finished: true)
            return
        }
        CreditLedger.shared.charge(.transcript, quantity: current.audioSeconds ?? 0, noteId: noteId)
        publish()

        // 2. Debrief. A failure here degrades: the transcript stands on its own.
        working = "Writing the debrief"
        started = Date()
        current.steps.append(StepRecord(name: "Debrief", outcome: .running, seconds: 0, note: ""))
        publish()
        let words = DebriefPrompt.wordCount(transcript.lines)
        if words < DebriefPrompt.minimumWords {
            finish(&current, outcome: .degraded, since: started,
                   note: "Too short to summarise (\(words) words): the transcript is the whole note.")
            publish(finished: true)
            return
        }
        guard let contextSize = OnDeviceModel.contextSize else {
            finish(&current, outcome: .degraded, since: started, note: OnDeviceModel.status.text)
            publish(finished: true)
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
            CreditLedger.shared.charge(.debrief, noteId: noteId)
            current.debriefHasAllSections = DebriefPrompt.hasAllSections(debrief)
            let note = chunks.count > 1 ? "Read in \(chunks.count) parts" : "One request"
            finish(&current, outcome: current.debriefHasAllSections ? .done : .degraded, since: started,
                   note: current.debriefHasAllSections ? note : note + "; the model did not keep the three headings")
        } catch {
            finish(&current, outcome: .degraded, since: started, note: error.localizedDescription)
        }
        publish(finished: true)
    }

    /// Once a note is finished, its WAV recording is replaced by a small .m4a. The WAV stays if that fails.
    private func compressAudio(of noteId: String) {
        guard let wav = store.audioURL(for: noteId), wav.pathExtension.lowercased() == "wav" else {
            noteReady(noteId)
            return
        }
        let m4a = store.folderURL(for: noteId).appending(path: "audio.m4a")
        compressing.insert(noteId)
        Task {
            let done = await Task.detached(priority: .utility) { () -> Bool in
                (try? AudioCompressor.compress(wav: wav, to: m4a)) != nil
            }.value
            if done, !isBusyWith(noteId) { store.replaceAudio(noteId, with: "audio.m4a") }
            compressing.remove(noteId)
            noteReady(noteId)
        }
    }

    /// True while this note is the one being recorded or processed: its audio must not be swapped then.
    private func isBusyWith(_ noteId: String) -> Bool {
        noteId == recordingNoteId || (noteId == currentNoteId && working != nil) || waiting.contains(noteId)
    }

    private func setWorking(_ text: String) {
        if working != nil { working = text }
    }

    private func finish(_ run: inout DebriefRun, outcome: StepRecord.Outcome, since: Date, note: String) {
        guard !run.steps.isEmpty else { return }
        let last = run.steps.count - 1
        run.steps[last].outcome = outcome
        run.steps[last].seconds = Date().timeIntervalSince(since)
        run.steps[last].note = note
    }

    func clearFailure() {
        failure = nil
    }

    // MARK: Sending

    /// Notes waiting to be sent as soon as they are finished, and to whom: note id to recipient name.
    private(set) var queuedSends: [String: String] = [:]
    private var queuedLanes: [String: DeveloperLane] = [:]
    /// Notes whose recording is being compressed right now.
    private var compressing: Set<String> = []

    /// Sends a note to a recipient. A note that is still being recorded, transcribed or compressed is
    /// sent the moment it is finished, so the button can be pressed at once and the phone put away.
    func send(noteId: String, to recipient: Recipient) {
        guard let lane = recipient.lane, let note = store.note(noteId) else { return }
        if note.processing || isBusyWith(noteId) || compressing.contains(noteId) {
            queuedLanes[noteId] = lane
            queuedSends[noteId] = recipient.name
        } else {
            Task { await share(noteId: noteId, lane: lane, to: recipient.name) }
        }
    }

    func cancelQueuedSend(_ noteId: String) {
        queuedLanes[noteId] = nil
        queuedSends[noteId] = nil
    }

    /// A note is finished and its audio is in its final form: send it if that was asked for, then tell
    /// whoever else is waiting (the automatic save to a vault).
    private func noteReady(_ noteId: String) {
        let name = queuedSends.removeValue(forKey: noteId) ?? ""
        if let lane = queuedLanes.removeValue(forKey: noteId) {
            Task { await share(noteId: noteId, lane: lane, to: name) }
        }
        onNoteReady?(noteId)
    }


    /// Sends the last note's audio, transcript and debrief to the developer's lane, encrypted to the
    /// developer's key. Only ever called from the button that says so.
    func share(noteId: String, lane: DeveloperLane, to name: String = "") async {
        // Sends go one at a time, in the order asked for: several notes finished and sent in quick
        // succession (issue 026) must all go, not only the first.
        outbox.append((noteId, lane, name))
        guard !draining else { return }
        draining = true
        while !outbox.isEmpty {
            let job = outbox.removeFirst()
            await sendNow(noteId: job.noteId, lane: job.lane, name: job.name)
        }
        draining = false
    }

    private var outbox: [(noteId: String, lane: DeveloperLane, name: String)] = []
    private var draining = false

    /// Who is being sent to over the network right now, for the screen that shows where work happens.
    private(set) var sendingTo: String?

    private func sendNow(noteId: String, lane: DeveloperLane, name: String) async {
        guard let note = store.note(noteId), let url = store.audioURL(for: noteId) else { return }
        sendingTo = name.isEmpty ? "lane \(lane.vault)" : name
        defer { sendingTo = nil }
        sharingNoteId = noteId
        sharing = .sending(0, 0)
        do {
            let audio = try Data(contentsOf: url)
            let messages = try DeveloperLane.messages(audio: audio, audioName: url.lastPathComponent, run: note.run, clean: note.clean,
                                                      noteId: noteId, app: AppInfo.versionLine(), at: Date())
            try await lane.send(messages) { done, total in
                Task { @MainActor [weak self] in self?.sharing = .sending(done, total) }
            }
            sharing = .sent(messages.count)
            store.recordSend(noteId, to: name.isEmpty ? "lane \(lane.vault)" : name)
            CreditLedger.shared.charge(.send, noteId: noteId)
        } catch {
            sharing = .failed(error.localizedDescription)
        }
    }

    /// The sending state as it applies to one note.
    func sharing(for noteId: String) -> Sharing {
        noteId == sharingNoteId ? sharing : .idle
    }
}

#if DEBUG
// A seam for the screenshots (issue 016, owned by the work/screens session). The states below are
// private(set), so sample values have to be set from this file. Called only by `SampleWorld`, which
// exists only when the app is launched with -VDSampleData; not compiled into a release build.
extension DebriefSession {
    func showSample(phase: Phase, noteId: String? = nil, waiting: [String] = [],
                    liveSettled: String = "", liveVolatile: String = "", levels: [Double] = []) {
        switch phase {
        case .recording(let since): recordingSince = since; working = nil; failure = nil
        case .working(let text): recordingSince = nil; working = text; failure = nil
        case .failed(let why): recordingSince = nil; working = nil; failure = why
        case .idle: recordingSince = nil; working = nil; failure = nil
        }
        self.currentNoteId = noteId
        self.waiting = waiting
        self.liveSettled = liveSettled
        self.liveVolatile = liveVolatile
        self.levels = levels
    }
}
#endif
