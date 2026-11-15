import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// No tools at all: a request for words and nothing else.
struct LabNoToolkit: ModelDoorToolkit {
    var definitions: [ModelDoorToolDefinition] { [] }

    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool] { [] }
    #endif
}

/// Experiment L07, edit with Apple Intelligence: a text, a request, and the model's proposed text,
/// shown as the change it makes. The code owns the text: nothing replaces it until the person
/// accepts, and a note it was taken from is never touched.
@MainActor
@Observable
final class LabEditDesk {
    static let shared = LabEditDesk()

    /// The text being worked on. Only an accepted edit, or the person, changes it.
    var text = ""
    /// Newest first.
    private(set) var turns: [LabEditTurn] = []
    private(set) var busy = false
    /// Names the model may be told about, for requests about names. Set by the screen.
    var names: [String] = []
    private var count = 0

    /// The proposal waiting for the person, if there is one.
    var waiting: LabEditTurn? { turns.first { $0.state == .proposed } }

    /// Asks the model for the edited text, through the model door, in a new session with no tools.
    func propose(_ request: String, now: Date = Date()) async {
        let wanted = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = text
        guard !busy, waiting == nil, !wanted.isEmpty, !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true
        defer { busy = false }
        let door = ModelDoorRequest(instructions: LabEditPrompt.instructions,
                                    prompt: LabEditPrompt.prompt(request: wanted, text: before, names: names),
                                    policy: .noTools)
        let record = await ModelDoor.ask(door, toolkit: LabNoToolkit())
        var turn = begin(wanted, before: before, now: now)
        turn.take(record)
        turns.insert(turn, at: 0)
    }

    /// A new turn for the text as it stands.
    func begin(_ request: String, before: String, now: Date = Date()) -> LabEditTurn {
        count += 1
        var turn = LabEditTurn(number: count, at: now, request: request, before: before)
        turn.cut = before.count > LabEditPrompt.longest
        return turn
    }

    /// Puts a turn at the top of the list. Used once the model has answered.
    func add(_ turn: LabEditTurn) { turns.insert(turn, at: 0) }

    /// The proposed text becomes the text, if the text is still what the proposal was made from.
    func accept(_ number: Int) {
        guard let index = turns.firstIndex(where: { $0.number == number }), turns[index].state == .proposed else { return }
        guard turns[index].before == text else {
            turns[index].reject()
            return
        }
        turns[index].accept()
        text = turns[index].after
    }

    func reject(_ number: Int) {
        guard let index = turns.firstIndex(where: { $0.number == number }) else { return }
        turns[index].reject()
    }

    /// Puts back the text an accepted edit replaced, if the text is still that edit's.
    func undo(_ number: Int) {
        guard let turn = turns.first(where: { $0.number == number }), turn.state == .accepted, text == turn.after else { return }
        text = turn.before
    }

    func clear() {
        turns = []
        count = 0
    }

    var log: LabEditLog {
        LabEditLog(device: LabDevice(appVersion: AppInfo.versionLine(),
                                     system: ProcessInfo.processInfo.operatingSystemVersionString,
                                     machine: Diagnostics.machineIdentifier(),
                                     modelStatus: OnDeviceModel.status.text,
                                     modelContextSize: OnDeviceModel.contextSize),
                   instructions: LabEditPrompt.instructions,
                   turns: turns)
    }
}
