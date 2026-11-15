import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The tools of experiments L05 and L06: one for each kind of thing a question can be about. A tool
/// looks nothing up. Calling it is how the model says what the question asks for; the code does the looking.
struct LabAskToolkit: ModelDoorToolkit {
    static let reply = LabToolResult(text: "Noted. The app will look it up.", ok: true)

    var definitions: [ModelDoorToolDefinition] {
        LabAskKind.allCases.map { ModelDoorToolDefinition(name: $0.rawValue, description: $0.summary) }
    }

    #if canImport(FoundationModels)
    func tools(named names: [String], recorder: ModelDoorRecorder) -> [any Tool] {
        LabAskKind.allCases.filter { names.contains($0.rawValue) }.map { kind -> any Tool in
            switch kind {
            case .tasks: return LabFindTasksTool(recorder: recorder)
            case .notes: return LabFindNotesTool(recorder: recorder)
            case .sent: return LabFindSentTool(recorder: recorder)
            case .person: return LabFindPersonTool(recorder: recorder)
            case .decisions: return LabFindDecisionsTool(recorder: recorder)
            }
        }
    }
    #endif
}

#if canImport(FoundationModels)
struct LabFindTasksTool: Tool {
    let name = LabAskKind.tasks.rawValue
    let description = LabAskKind.tasks.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The subject asked about, in a few words. The single word none if no subject was named.")
        let about: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["about": arguments.about]) { LabAskToolkit.reply }
    }
}

struct LabFindNotesTool: Tool {
    let name = LabAskKind.notes.rawValue
    let description = LabAskKind.notes.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The subject asked about, in a few words. The single word none if no subject was named.")
        let about: String
        @Guide(description: "When the notes were recorded", .anyOf(["any time", "today", "yesterday", "this week"]))
        let when: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["about": arguments.about, "when": arguments.when]) { LabAskToolkit.reply }
    }
}

struct LabFindSentTool: Tool {
    let name = LabAskKind.sent.rawValue
    let description = LabAskKind.sent.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The subject asked about, in a few words. The single word none if no subject was named.")
        let about: String
        @Guide(description: "When it was sent", .anyOf(["any time", "today", "yesterday", "this week"]))
        let when: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: ["about": arguments.about, "when": arguments.when]) { LabAskToolkit.reply }
    }
}

struct LabFindPersonTool: Tool {
    let name = LabAskKind.person.rawValue
    let description = LabAskKind.person.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {
        @Guide(description: "The name of the person or agent, as it was said")
        let name: String
    }

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: self.name, arguments: ["name": arguments.name]) { LabAskToolkit.reply }
    }
}

struct LabFindDecisionsTool: Tool {
    let name = LabAskKind.decisions.rawValue
    let description = LabAskKind.decisions.summary
    let recorder: ModelDoorRecorder

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        recorder.measure(tool: name, arguments: [:]) { LabAskToolkit.reply }
    }
}
#endif

/// Questions about the app's own data, for L05 and L06. One question at a time: the model is asked
/// which kind of thing it is (one tool for each kind, a new session each time), the code walks the
/// data and builds the answer from what it found. The model never sees the data and writes none of the answer.
@MainActor
@Observable
final class LabAskDesk {
    /// L06, where each step is laid out, and L05, where the answer is spoken. Each keeps its own log.
    static let discovery = LabAskDesk(experiment: "L06")
    static let talk = LabAskDesk(experiment: "L05")

    let experiment: String
    /// Newest first.
    private(set) var turns: [LabAskTurn] = []
    private(set) var busy = false
    var askModel = true
    /// The app's data as it is now. Set by the screen.
    var world: @MainActor () -> LabWorld = { LabWorld(now: Date()) }
    private var count = 0

    init(experiment: String) {
        self.experiment = experiment
    }

    /// One question, taken all the way to its answer. Returns nil while another is being answered.
    @discardableResult
    func ask(_ question: String, source: String, now: Date = Date()) async -> LabAskTurn? {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !LabTriggerMatcher.words(text).isEmpty else { return nil }
        busy = true
        defer { busy = false }
        count += 1
        let snapshot = world()
        var turn = LabAskTurn(number: count, at: now, question: text, source: source)
        turn.rules = LabAskRules.classify(text, people: snapshot.people)
        if askModel {
            turn.modelAsked = true
            let request = ModelDoorRequest(instructions: LabAskPrompt.instructions, prompt: text,
                                           policy: ModelDoorPolicy(allowedTools: LabAskKind.allCases.map(\.rawValue)))
            let record = await ModelDoor.ask(request, toolkit: LabAskToolkit())
            turn.take(record, people: snapshot.people)
        }
        turn.settle(in: snapshot)
        turns.insert(turn, at: 0)
        return turn
    }

    /// Notes how long the answer took to say, once it has been said.
    func spoke(_ number: Int, ms: Double) {
        guard let index = turns.firstIndex(where: { $0.number == number }) else { return }
        turns[index].spokeMs = ms
    }

    func clear() {
        turns = []
        count = 0
    }

    var log: LabAskLog {
        LabAskLog(experiment: experiment,
                  device: LabDevice(appVersion: AppInfo.versionLine(),
                                    system: ProcessInfo.processInfo.operatingSystemVersionString,
                                    machine: Diagnostics.machineIdentifier(),
                                    modelStatus: OnDeviceModel.status.text,
                                    modelContextSize: OnDeviceModel.contextSize),
                  instructions: LabAskPrompt.instructions,
                  turns: turns)
    }

    /// The app's data, copied out: the library, the contacts, and the last agents report with what was sent to agents.
    static func world(store: NoteStore, now: Date = Date()) -> LabWorld {
        let report = AgentsDesk.shared.report
        let names = Dictionary((report?.agents ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var messages = (report?.messages ?? []).map {
            LabWorld.MessageItem(id: $0.id, agent: names[$0.agent] ?? $0.agent, fromYou: $0.from == "you", at: $0.at, text: $0.text, quote: $0.quote)
        }
        messages += AgentsDesk.shared.sent.filter { sent in !messages.contains { $0.id == sent.id } }.map {
            LabWorld.MessageItem(id: $0.id, agent: names[$0.agent] ?? $0.agent, fromYou: true, at: $0.at, text: $0.text, quote: nil)
        }
        return LabWorld(
            now: now,
            notes: store.notes.map { note in
                LabWorld.NoteItem(id: note.id, createdAt: note.createdAt, title: note.title,
                                  transcript: note.run.transcript?.lines.map(\.text).joined(separator: " ") ?? "",
                                  actions: LabWorld.actions(in: note.run.debrief),
                                  sends: (note.sends ?? []).map { LabWorld.Send(to: $0.to, at: $0.at) },
                                  pendingTo: note.pendingSend?.name, sendProblem: note.sendProblem)
            },
            contacts: RecipientStore.shared.all.map(\.name),
            agents: (report?.agents ?? []).map {
                LabWorld.AgentItem(id: $0.id, name: $0.name, status: $0.status, doing: $0.doing, waitingFor: $0.waitingFor)
            },
            messages: messages)
    }
}
