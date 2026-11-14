import AVFoundation
import Foundation
import Observation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The tools of experiment L04: one for each label in use. A tool changes nothing: it records the
/// value the model offered, and the board decides what to do with it.
struct LabLabelToolkit: ModelDoorToolkit {
    let fields: [LabLabelField]

    static let reply = LabToolResult(text: "Noted.", ok: true)

    var definitions: [ModelDoorToolDefinition] {
        fields.map { ModelDoorToolDefinition(name: $0.tool, description: $0.summary) }
    }

    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool] {
        fields.filter { names.contains($0.tool) }.map { field -> any Tool in
            switch field.id {
            case "urgency": return LabLabelUrgencyTool(name: field.tool, description: field.summary, recorder: recorder)
            case "kind": return LabLabelKindTool(name: field.tool, description: field.summary, recorder: recorder)
            default: return LabLabelTextTool(name: field.tool, description: field.summary, recorder: recorder)
            }
        }
    }
    #endif
}

#if canImport(FoundationModels)
/// A label that holds words. One type serves every such label: the name and the description are its own.
struct LabLabelTextTool: Tool {
    let name: String
    let description: String
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The value for this label, in a few words taken from the note")
        let value: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["value": arguments.value]) { LabLabelToolkit.reply }
    }
}

struct LabLabelUrgencyTool: Tool {
    let name: String
    let description: String
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "How urgent the note is", .anyOf(["low", "normal", "high"]))
        let value: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["value": arguments.value]) { LabLabelToolkit.reply }
    }
}

struct LabLabelKindTool: Tool {
    let name: String
    let description: String
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "What kind of note it is", .anyOf(["memo", "idea", "task", "question", "update"]))
        let value: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["value": arguments.value]) { LabLabelToolkit.reply }
    }
}
#endif

/// The Lab's ear: the live words from the microphone, with the rules learned in L02 (issue 047).
/// It never switches the shared audio session off, does not start while a note is being recorded,
/// gives up a start that a stop overtook, and stops when the app leaves the foreground.
@MainActor
final class LabListener {
    private let host: LabActionHost
    private let live = LiveTranscriber()
    private var wanted = false
    private(set) var listening = false
    /// Called with the settled words so far and the words that may still change.
    var onWords: ((String, String) -> Void)?
    /// Called when listening ends for any reason, the app going to the background included.
    var onStop: (() -> Void)?

    init(host: LabActionHost? = nil) {
        self.host = host ?? LabActionHost.shared
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.stop() }
        }
    }

    /// Starts listening. Returns nil when it did, or the reason it did not, in plain words.
    func start(localeId: String) async -> String? {
        guard !listening, !wanted else { return nil }
        if host.isRecording?() == true { return "A note is being recorded. The Lab does not listen at the same time." }
        guard !localeId.isEmpty else { return "Choose the language spoken in Settings first." }
        wanted = true
        guard await AVAudioApplication.requestRecordPermission() else {
            wanted = false
            return "The microphone is not allowed for this app."
        }
        guard wanted, host.isRecording?() != true else {
            wanted = false
            return nil
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            listening = true
            try await live.start(localeId: localeId) { [weak self] settled, volatile in
                Task { @MainActor [weak self] in
                    guard let self, self.listening else { return }
                    self.onWords?(settled, volatile)
                }
            }
            if !wanted {
                listening = false
                await live.stop()
            }
            return nil
        } catch {
            wanted = false
            listening = false
            await live.stop()
            return "Listening could not start: \(error.localizedDescription)"
        }
    }

    func stop() async {
        wanted = false
        guard listening else { return }
        listening = false
        // The tap and the engine stop before this first suspends; the audio session is left alone.
        await live.stop()
        onStop?()
    }
}

/// Experiment L04, live labels: while a note is spoken, the model is asked every few seconds to
/// fill in a small set of labels from a window of the words so far, one tool for each label, in a
/// new session each time. The board (the code) owns the labels: what the person says a label is
/// stands, and the model cannot move it. Every loop is timed and kept.
@MainActor
@Observable
final class LabLabelsDesk {
    static let shared = LabLabelsDesk()

    private static let chosenKey = "vd.lab.labels.chosen"
    private static let secondsKey = "vd.lab.labels.seconds"
    private static let windowKey = "vd.lab.labels.window"
    static let secondsChoices = [3, 5, 10]
    /// In tokens; 0 is everything said so far.
    static let windowChoices = [250, 500, 1000, 0]

    private(set) var board = LabLabelBoard()
    /// Newest first.
    private(set) var loops: [LabLabelLoop] = []
    private(set) var overrides: [LabLabelOverrideEntry] = []
    private(set) var chosen: Set<String>
    var seconds: Int { didSet { defaults.set(seconds, forKey: Self.secondsKey) } }
    var windowTokens: Int { didSet { defaults.set(windowTokens, forKey: Self.windowKey) } }
    /// Contacts and agents the note can be for. Set by the screen.
    var candidates: [LabLabelCandidate] = []

    private(set) var running = false
    private(set) var looping = false
    private(set) var settled = ""
    private(set) var volatile = ""
    private(set) var typed = ""
    private(set) var problem: String?
    /// The labels the newest loop changed, for the screen to mark.
    var lastChanged: Set<String> { Set(loops.first?.changed ?? []) }

    private let defaults: UserDefaults
    private let listener: LabListener
    private var consumed = 0
    private var asked = ""
    private var timer: Task<Void, Never>?
    private var count = 0

    init(defaults: UserDefaults = .standard, host: LabActionHost? = nil) {
        self.defaults = defaults
        listener = LabListener(host: host)
        chosen = Set(defaults.stringArray(forKey: Self.chosenKey) ?? Array(LabLabelField.firstChoice))
        let savedSeconds = defaults.integer(forKey: Self.secondsKey)
        seconds = Self.secondsChoices.contains(savedSeconds) ? savedSeconds : 5
        let savedWindow = defaults.object(forKey: Self.windowKey) as? Int
        windowTokens = savedWindow.flatMap { Self.windowChoices.contains($0) ? $0 : nil } ?? 1000
        listener.onWords = { [weak self] settled, volatile in self?.heard(settled: settled, volatile: volatile) }
        listener.onStop = { [weak self] in self?.stopped() }
    }

    var inUse: [LabLabelField] { LabLabelField.inUse(chosen) }

    func setChosen(_ fieldId: String, _ on: Bool) {
        guard LabLabelField.find(fieldId)?.always == false else { return }
        if on { chosen.insert(fieldId) } else { chosen.remove(fieldId) }
        defaults.set(chosen.sorted(), forKey: Self.chosenKey)
    }

    /// Everything said so far: what was typed, what has settled, and what may still change.
    var transcript: String {
        [typed, settled, volatile].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Words in

    /// Starts the microphone and the loops. Nothing is recorded: only the words are kept, in memory.
    func start(localeId: String) async {
        guard !running else { return }
        problem = await listener.start(localeId: localeId)
        guard listener.listening else { return }
        running = true
        timer = Task { [weak self] in
            while !Task.isCancelled, let self, self.running {
                try? await Task.sleep(for: .seconds(self.seconds))
                if Task.isCancelled || !self.running { break }
                await self.loop()
            }
        }
    }

    func stop() async {
        await listener.stop()
        stopped()
        // What was said last is looked at once more.
        await loop()
    }

    private func stopped() {
        guard running else { return }
        running = false
        timer?.cancel()
        timer = nil
        // Words that never settled are still what was said.
        scanForOverrides(volatile)
    }

    private func heard(settled: String, volatile: String) {
        self.settled = settled
        self.volatile = volatile
        if let piece = LabUtterances.fresh(settled: settled, consumed: consumed) {
            consumed = piece.consumed
            scanForOverrides(piece.text)
        }
    }

    /// Words typed in place of speech, for a device with no microphone to hand and for trying a sentence again.
    func type(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = typed.isEmpty ? text : typed + " " + text
        scanForOverrides(text)
    }

    /// The code listens for the person setting a label. What they say stands, at once, and is pinned.
    private func scanForOverrides(_ sentence: String, now: Date = Date()) {
        for found in LabLabelOverrides.detect(sentence, inUse: inUse) {
            if board.override(found.value, for: found.field, candidates: candidates) {
                overrides.insert(LabLabelOverrideEntry(at: now, field: found.field, value: found.value, sentence: sentence), at: 0)
            }
        }
    }

    func setByHand(_ fieldId: String, _ text: String) {
        board.override(text, for: fieldId, source: "hand", candidates: candidates)
    }

    func unpin(_ fieldId: String) { board.unpin(fieldId) }

    // MARK: The loop

    /// One question to the model about the words so far. Skipped when nothing new has been said
    /// since the last one, unless it is forced.
    func loop(force: Bool = false) async {
        let said = transcript
        guard !looping, !said.isEmpty, force || said != asked else { return }
        looping = true
        defer { looping = false }
        asked = said
        count += 1
        let number = count
        let fields = inUse
        let window = LabLabelWindow.take(said, tokens: windowTokens)
        let request = ModelDoorRequest(
            instructions: LabLabelPrompt.instructions,
            prompt: LabLabelPrompt.prompt(board: board, inUse: fields, candidates: candidates, window: window),
            policy: ModelDoorPolicy(allowedTools: fields.map(\.tool)))
        let record = await ModelDoor.ask(request, toolkit: LabLabelToolkit(fields: fields))
        take(record, number: number, window: window, transcript: said, fields: fields)
    }

    /// A loop's answer is applied to the board as it stands now: a label the person pinned while the
    /// model was thinking is not moved.
    func take(_ record: ModelDoorRecord, number: Int, window: String, transcript: String, fields: [LabLabelField]) {
        let entry = LabLabelLoop.apply(record, to: &board, number: number, windowTokens: windowTokens, window: window,
                                       transcript: transcript, inUse: fields, candidates: candidates)
        loops.insert(entry, at: 0)
    }

    /// A new note: the labels, the words and the pins go; the log of loops stays.
    func startAgain() {
        board = LabLabelBoard()
        overrides = []
        settled = ""
        volatile = ""
        typed = ""
        consumed = 0
        asked = ""
    }

    func clearLog() {
        loops = []
        count = 0
    }

    var log: LabLabelLog {
        LabLabelLog(device: LabDevice(appVersion: AppInfo.versionLine(),
                                      system: ProcessInfo.processInfo.operatingSystemVersionString,
                                      machine: Diagnostics.machineIdentifier(),
                                      modelStatus: OnDeviceModel.status.text,
                                      modelContextSize: OnDeviceModel.contextSize),
                    instructions: LabLabelPrompt.instructions,
                    labels: inUse.map(\.id),
                    secondsBetweenLoops: seconds,
                    windowTokens: windowTokens,
                    board: board,
                    overrides: overrides,
                    loops: loops)
    }
}
