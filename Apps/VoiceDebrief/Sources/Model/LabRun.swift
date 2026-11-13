import Foundation

/// The tools the Lab can offer the model. The raw value is the name the model sees.
enum LabToolId: String, Codable, CaseIterable, Sendable, Identifiable {
    case clock = "currentDateTime"
    case listNotes = "listNotes"
    case readNote = "readNote"
    case chooseScreen = "chooseNextScreen"

    var id: String { rawValue }

    /// What a person reads next to the switch.
    var title: String {
        switch self {
        case .clock: return "Date and time"
        case .listNotes: return "List my notes"
        case .readNote: return "Read one note"
        case .chooseScreen: return "Choose the next screen"
        }
    }

    /// The description the model is given. Literal and short: it is counted against the context.
    var summary: String {
        switch self {
        case .clock: return "Gives the current date and time on this device."
        case .listNotes: return "Lists my voice notes, newest first, with the id, the date and the title of each."
        case .readNote: return "Gives the transcript of one voice note, found by its id."
        case .chooseScreen: return "Chooses which screen the app shows next."
        }
    }
}

/// The screens the model may choose between. The choice is recorded and shown; nothing acts on it.
enum LabScreen {
    static let names = ["record", "library", "note", "vaults", "settings"]
}

/// A tool as it was offered to the model: its name and the description it was given.
struct ModelDoorToolDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
}

/// One call the model made to a tool, as the tool itself saw it.
struct ModelDoorToolCall: Codable, Equatable, Sendable, Identifiable {
    /// The order in which the calls arrived, from 1.
    let order: Int
    let name: String
    let arguments: [String: String]
    let result: String
    /// False when the tool could not do what was asked, such as a note id that does not exist.
    let ok: Bool
    let durationMs: Double

    var id: Int { order }
}

/// Why a request did not end in an answer, in plain words, with what the framework said.
struct ModelDoorError: Codable, Equatable, Sendable {
    /// unavailable, guardrail, refusal, contextExceeded, toolFailed, rateLimited, language, noSDK or other.
    let kind: String
    let words: String
    let raw: String

    /// Sorts an error into a kind from its own description. Used for errors whose type this build
    /// does not know by name, so a newer framework's errors still come out in plain words.
    static func classify(raw: String, description: String) -> ModelDoorError {
        let lower = raw.lowercased()
        if lower.contains("guardrail") {
            return ModelDoorError(kind: "guardrail", words: "Apple's safety guardrails stopped this request.", raw: raw)
        }
        if lower.contains("refusal") {
            return ModelDoorError(kind: "refusal", words: "The model refused to answer.", raw: raw)
        }
        if lower.contains("contextwindow") || lower.contains("contextsize") {
            return ModelDoorError(kind: "contextExceeded", words: "The instructions, the prompt, the tools and their results together were too long for the model's context.", raw: raw)
        }
        if lower.contains("ratelimited") {
            return ModelDoorError(kind: "rateLimited", words: "The system is limiting requests to the model just now.", raw: raw)
        }
        if lower.contains("unsupportedlanguage") {
            return ModelDoorError(kind: "language", words: "The model does not support the language of this request.", raw: raw)
        }
        if lower.contains("assetsunavailable") {
            return ModelDoorError(kind: "unavailable", words: "The model's files are not on this device just now.", raw: raw)
        }
        return ModelDoorError(kind: "other", words: description, raw: raw)
    }
}

/// What the model door will allow for one request: which tools are offered.
struct ModelDoorPolicy: Codable, Equatable, Sendable {
    /// The names of the tools this request may use. Nothing else is offered.
    var allowedTools: [String]

    static let noTools = ModelDoorPolicy(allowedTools: [])

    init(allowedTools: [String]) {
        self.allowedTools = allowedTools.sorted()
    }

    init(tools: Set<LabToolId>) {
        self.init(allowedTools: tools.map(\.rawValue))
    }

    func allows(_ name: String) -> Bool { allowedTools.contains(name) }

    /// The tools of a catalogue that this policy lets through, in the catalogue's order.
    func offered(from catalogue: [LabToolId]) -> [LabToolId] { catalogue.filter { allows($0.rawValue) } }

    /// The tools of a catalogue that exist and were kept back.
    func withheld(from catalogue: [LabToolId]) -> [LabToolId] { catalogue.filter { !allows($0.rawValue) } }
}

/// One request to the model, as the door is asked to make it.
struct ModelDoorRequest: Equatable, Sendable {
    var instructions: String
    var prompt: String
    var policy: ModelDoorPolicy
}

/// Everything that passed through the model door for one request.
struct ModelDoorRecord: Codable, Equatable, Sendable {
    var startedAt: Date
    var instructions: String
    var prompt: String
    var policy: ModelDoorPolicy
    var toolsOffered: [ModelDoorToolDefinition]
    var toolsWithheld: [String]
    /// The calls the tools received, in order, with what each returned.
    var toolCalls: [ModelDoorToolCall] = []
    /// The tool names in the session's own transcript: what the model asked for, whether or not a tool ran.
    var modelToolRequests: [String] = []
    var answer: String?
    var error: ModelDoorError?
    var totalMs: Double = 0
    /// The session's transcript, one entry each, as the framework describes it.
    var transcript: [String] = []
}

/// What the device said about itself when a run was made.
struct LabDevice: Codable, Equatable, Sendable {
    var appVersion: String
    var system: String
    var machine: String
    var modelStatus: String
    var modelContextSize: Int?
}

/// One run of experiment L01: one prompt, a chosen set of tools, and the full record.
struct LabRun: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var experiment: String = "L01"
    /// The preset this run was started from, if any.
    var presetId: String?
    /// The tools that preset expects the model to call.
    var expectedTools: [String]?
    var device: LabDevice
    var record: ModelDoorRecord

    /// The screen the model chose, if it used that tool with a name on the list. Shown, never acted on.
    var screenChoice: String? {
        record.toolCalls.last { $0.name == LabToolId.chooseScreen.rawValue && $0.ok }?.arguments["screen"]
    }

    var calledTools: [String] { record.toolCalls.map(\.name) }

    var verdict: LabVerdict? {
        guard let expectedTools else { return nil }
        return LabVerdict.judge(expected: expectedTools, offered: record.toolsOffered.map(\.name),
                                called: calledTools, failed: record.error != nil)
    }

    var json: String { LabRun.json(of: self) }

    static func json<T: Encodable>(of value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func decode(_ json: String) -> LabRun? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LabRun.self, from: Data(json.utf8))
    }
}

/// Whether the model called the tools a preset expects. Only the choice of tool is judged: the
/// quality of the answer is for a person to read.
enum LabVerdict: Equatable, Sendable {
    /// It called every expected tool, or none when none could or should be called.
    case right
    /// It did not call these expected tools, though they were offered.
    case missed([String])
    /// It called these tools when no call was expected.
    case unneeded([String])
    /// The request ended in an error, so there is nothing to judge.
    case failed

    static func judge(expected: [String], offered: [String], called: [String], failed: Bool) -> LabVerdict {
        if failed { return .failed }
        let calledSet = Set(called)
        // A preset whose tool is switched off, or that needs no tool, is answered rightly with no call.
        if expected.isEmpty || expected.contains(where: { !offered.contains($0) }) {
            return calledSet.isEmpty ? .right : .unneeded(calledSet.sorted())
        }
        let missing = expected.filter { !calledSet.contains($0) }
        return missing.isEmpty ? .right : .missed(missing)
    }

    var isRight: Bool { self == .right }

    var words: String {
        switch self {
        case .right: return "Tool choice as expected"
        case .missed(let names): return "Did not call \(names.joined(separator: ", "))"
        case .unneeded(let names): return "Called \(names.joined(separator: ", ")) when no call was expected"
        case .failed: return "Ended in an error"
        }
    }
}

/// A prompt kept ready, with the tools it is run with and the tools a reliable model would call.
struct LabPreset: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let prompt: String
    let tools: Set<LabToolId>
    let expects: [LabToolId]

    static let all: [LabPreset] = [
        LabPreset(id: "date", title: "The date today",
                  prompt: "What is the date today?",
                  tools: Set(LabToolId.allCases), expects: [.clock]),
        LabPreset(id: "mention", title: "Notes that mention a word",
                  prompt: "Which of my notes mention the word vault?",
                  tools: Set(LabToolId.allCases), expects: [.listNotes]),
        LabPreset(id: "recent", title: "My most recent note in one sentence",
                  prompt: "Summarise my most recent note in one sentence.",
                  tools: Set(LabToolId.allCases), expects: [.listNotes, .readNote]),
        LabPreset(id: "no-tool", title: "Needs no tool",
                  prompt: "What is 12 plus 30?",
                  tools: Set(LabToolId.allCases), expects: []),
        LabPreset(id: "tool-off", title: "Needs a tool that is switched off",
                  prompt: "What is the date today?",
                  tools: [.listNotes, .readNote, .chooseScreen], expects: [.clock]),
        LabPreset(id: "screen", title: "Choose the next screen",
                  prompt: "I want to look at the notes I have already recorded. Choose the screen for that.",
                  tools: Set(LabToolId.allCases), expects: [.chooseScreen]),
    ]

    static func find(_ id: String?) -> LabPreset? { all.first { $0.id == id } }
}

/// How often the tool choice was as expected, for each preset that has been run.
struct LabTally: Equatable, Sendable, Identifiable {
    let presetId: String
    let title: String
    let runs: Int
    let right: Int

    var id: String { presetId }

    static func of(_ runs: [LabRun]) -> [LabTally] {
        LabPreset.all.compactMap { preset in
            let mine = runs.filter { $0.presetId == preset.id }
            guard !mine.isEmpty else { return nil }
            return LabTally(presetId: preset.id, title: preset.title, runs: mine.count,
                            right: mine.filter { $0.verdict?.isRight == true }.count)
        }
    }
}

enum LabDefaults {
    /// The instructions a run starts with. Plain, with nothing the model could copy into its answer.
    static let instructions = "You answer questions about my voice notes. Use a tool when the answer needs information you do not have. Answer in one or two plain sentences."
}
