import AVFoundation
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The tools of experiment L02: one for each action. A tool carries nothing out. It records that
/// the model asked for the action, which is the model's answer.
struct LabControlToolkit: ModelDoorToolkit {
    static let reply = LabToolResult(text: "Noted. The person will be asked before anything is done.", ok: true)

    var definitions: [ModelDoorToolDefinition] {
        LabAction.allCases.map { ModelDoorToolDefinition(name: $0.rawValue, description: $0.summary) }
    }

    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool] {
        LabAction.allCases.filter { names.contains($0.rawValue) }.map { action -> any Tool in
            switch action {
            case .recordFor: return LabRecordForTool(recorder: recorder)
            case .sendTo: return LabSendToTool(recorder: recorder)
            case .finishRecording: return LabFinishRecordingTool(recorder: recorder)
            case .cancelLast: return LabCancelLastTool(recorder: recorder)
            case .openSection: return LabOpenSectionTool(recorder: recorder)
            case .saveToVault: return LabSaveToVaultTool(recorder: recorder)
            case .findNote: return LabFindNoteTool(recorder: recorder)
            }
        }
    }
    #endif
}

#if canImport(FoundationModels)
struct LabRecordForTool: Tool {
    let name = LabAction.recordFor.rawValue
    let description = LabAction.recordFor.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "How many minutes to record for", .range(1...120))
        let minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["minutes": "\(arguments.minutes)"]) { LabControlToolkit.reply }
    }
}

struct LabSendToTool: Tool {
    let name = LabAction.sendTo.rawValue
    let description = LabAction.sendTo.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The name of the person to send the note to, as it was said")
        let recipient: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["recipient": arguments.recipient]) { LabControlToolkit.reply }
    }
}

struct LabFinishRecordingTool: Tool {
    let name = LabAction.finishRecording.rawValue
    let description = LabAction.finishRecording.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: [:]) { LabControlToolkit.reply }
    }
}

struct LabCancelLastTool: Tool {
    let name = LabAction.cancelLast.rawValue
    let description = LabAction.cancelLast.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: [:]) { LabControlToolkit.reply }
    }
}

struct LabOpenSectionTool: Tool {
    let name = LabAction.openSection.rawValue
    let description = LabAction.openSection.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The section to show", .anyOf(["record", "library", "vaults", "settings"]))
        let section: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["section": arguments.section]) { LabControlToolkit.reply }
    }
}

struct LabSaveToVaultTool: Tool {
    let name = LabAction.saveToVault.rawValue
    let description = LabAction.saveToVault.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: [:]) { LabControlToolkit.reply }
    }
}

struct LabFindNoteTool: Tool {
    let name = LabAction.findNote.rawValue
    let description = LabAction.findNote.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The subject of the note to look for, in a few words")
        let words: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["words": arguments.words]) { LabControlToolkit.reply }
    }
}
#endif

/// Experiment L02, the control centre: sentences come in (spoken, typed or from the test set), each
/// is put to the fixed phrases and, one at a time, to the model, and each proposed action waits for
/// the person. The code owns the states. Nothing is carried out.
@MainActor
@Observable
final class LabControlCentre {
    static let shared = LabControlCentre()

    private static let triggersKey = "vd.lab.control.triggers"
    private static let automaticKey = "vd.lab.control.automatic"

    /// Newest first.
    private(set) var entries: [LabControlEntry] = []
    private(set) var triggers: [LabTrigger]
    private(set) var automatic: Set<String>
    var askModel = true

    private(set) var listening = false
    private(set) var liveSettled = ""
    private(set) var liveVolatile = ""
    private(set) var problem: String?
    private(set) var testing = false

    private let defaults: UserDefaults
    private let live = LiveTranscriber()
    private var consumed = 0
    private var waiting: [String] = []
    private var worker: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.triggersKey), let saved = try? JSONDecoder().decode([LabTrigger].self, from: data) {
            triggers = saved
        } else {
            triggers = LabTrigger.defaults
        }
        automatic = Set(defaults.stringArray(forKey: Self.automaticKey) ?? [])
    }

    // MARK: The phrases and what runs by itself

    func addTrigger(phrase: String, action: String) {
        let cleaned = LabTriggerMatcher.words(phrase).joined(separator: " ")
        guard !cleaned.isEmpty, !triggers.contains(where: { $0.phrase == cleaned }) else { return }
        triggers.append(LabTrigger(phrase: cleaned, action: action))
        saveTriggers()
    }

    func removeTriggers(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where triggers.indices.contains(index) { triggers.remove(at: index) }
        saveTriggers()
    }

    func restoreTriggers() {
        triggers = LabTrigger.defaults
        saveTriggers()
    }

    private func saveTriggers() {
        if let data = try? JSONEncoder().encode(triggers) { defaults.set(data, forKey: Self.triggersKey) }
    }

    func setAutomatic(_ action: String, _ on: Bool) {
        if on { automatic.insert(action) } else { automatic.remove(action) }
        defaults.set(automatic.sorted(), forKey: Self.automaticKey)
    }

    // MARK: Sentences in

    /// One sentence into the pipeline.
    @discardableResult
    func hear(_ words: String, source: String, expected: String? = nil, now: Date = Date()) -> String? {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !LabTriggerMatcher.words(text).isEmpty else { return nil }
        let entry = LabControlEntry(id: Note.newId(at: now), heardAt: now, words: text, source: source, expected: expected,
                                    triggers: triggers, askModel: askModel, automatic: automatic)
        entries.insert(entry, at: 0)
        if entry.state == .asking {
            waiting.append(entry.id)
            startWorker()
        }
        return entry.id
    }

    /// The model is asked about one sentence at a time, in the order they were heard.
    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let id = self.waiting.first {
                self.waiting.removeFirst()
                guard let words = self.entries.first(where: { $0.id == id })?.words else { continue }
                let request = ModelDoorRequest(instructions: LabControlDefaults.instructions, prompt: words,
                                               policy: ModelDoorPolicy(allowedTools: LabAction.allCases.map(\.rawValue)))
                let record = await ModelDoor.ask(request, toolkit: LabControlToolkit())
                self.update(id) { $0.receive(record, automatic: self.automatic) }
            }
            self?.worker = nil
        }
    }

    private func update(_ id: String, _ change: (inout LabControlEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    func doIt(_ id: String) { update(id) { $0.doIt() } }
    func notThis(_ id: String) { update(id) { $0.notThis() } }
    func edit(_ id: String, action: String, argument: String) { update(id) { $0.edit(action: action, argument: argument) } }

    /// The test sentences, one after another, each judged against the action it asks for.
    func runTests() async {
        guard !testing else { return }
        testing = true
        defer { testing = false }
        for test in LabControlTest.all {
            hear(test.words, source: "test", expected: test.expected)
        }
        while worker != nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func clear() {
        waiting = []
        entries = []
    }

    // MARK: Listening

    func startListening(localeId: String) async {
        guard !listening else { return }
        problem = nil
        guard !localeId.isEmpty else {
            problem = "Choose the language spoken in Settings first."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "The microphone is not allowed for this app."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            liveSettled = ""
            liveVolatile = ""
            consumed = 0
            listening = true
            try await live.start(localeId: localeId) { [weak self] settled, volatile in
                Task { @MainActor [weak self] in self?.heardLive(settled: settled, volatile: volatile) }
            }
        } catch {
            listening = false
            await live.stop()
            problem = "Listening could not start: \(error.localizedDescription)"
        }
    }

    func stopListening() async {
        guard listening else { return }
        listening = false
        await live.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // What was said last and had not settled is still a sentence.
        let rest = (String(liveSettled.dropFirst(consumed)) + " " + liveVolatile).trimmingCharacters(in: .whitespacesAndNewlines)
        hear(rest, source: "spoken")
        liveVolatile = ""
    }

    private func heardLive(settled: String, volatile: String) {
        guard listening else { return }
        liveSettled = settled
        liveVolatile = volatile
        if let piece = LabUtterances.fresh(settled: settled, consumed: consumed) {
            consumed = piece.consumed
            hear(piece.text, source: "spoken")
        }
    }

    // MARK: Export

    var log: LabControlLog {
        LabControlLog(device: LabDevice(appVersion: AppInfo.versionLine(),
                                        system: ProcessInfo.processInfo.operatingSystemVersionString,
                                        machine: Diagnostics.machineIdentifier(),
                                        modelStatus: OnDeviceModel.status.text,
                                        modelContextSize: OnDeviceModel.contextSize),
                      instructions: LabControlDefaults.instructions,
                      triggers: triggers,
                      automatic: automatic.sorted(),
                      entries: entries)
    }
}
