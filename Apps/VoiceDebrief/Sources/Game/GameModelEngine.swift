import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One request of the game to Apple's on-device model: what it was given, what it proposed, how long
/// it took. One fresh session per turn and no history.
struct GameModelTurn: Codable, Equatable, Sendable {
    /// rules or hint.
    var role: String
    var instructions: String
    var prompt: String
    var toolsOffered: [GameToolSpec]
    var tokens: GameTokenEstimate
    /// The session was made and prewarmed before the words arrived.
    var prewarmed = false
    /// The first tool call, which ends the request.
    var tool: String?
    var arguments: [String: String] = [:]
    var firstCallMs: Double?
    var totalMs: Double = 0
    var answer: String?
    var error: ModelDoorError?

    var energyMilliwattHours: Double { GameEnergy.milliwattHours(ms: totalMs) }
}

/// Holds the first tool call of a request. Tools may be called on any thread, so it is locked.
final class GameCallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var first: (tool: String, arguments: [String: String], at: Date)?

    func record(tool: String, arguments: [String: String]) {
        lock.lock()
        if first == nil { first = (tool, arguments, Date()) }
        lock.unlock()
    }

    var call: (tool: String, arguments: [String: String], at: Date)? {
        lock.lock()
        defer { lock.unlock() }
        return first
    }
}

/// Thrown by a tool once it has recorded its call: the request stops there, so nothing after the
/// call is generated. Time and energy saved, and the call is all the game needs.
struct GameToolStop: Error {}

#if canImport(FoundationModels)
struct GameMoveTool: Tool {
    let name: String
    let description: String
    let box: GameCallBox

    @Generable
    struct Arguments {
        @Guide(description: "The direction", .anyOf(["up", "down", "left", "right"]))
        let direction: String
        @Guide(description: "How many squares", .range(1...9))
        let steps: Int
    }

    func call(arguments: Arguments) async throws -> String {
        box.record(tool: name, arguments: ["direction": arguments.direction, "steps": "\(arguments.steps)"])
        throw GameToolStop()
    }
}

struct GameJumpTool: Tool {
    let name: String
    let description: String
    let box: GameCallBox

    @Generable
    struct Arguments {
        @Guide(description: "Which way to jump", .anyOf(["left", "right", "up"]))
        let direction: String
    }

    func call(arguments: Arguments) async throws -> String {
        box.record(tool: name, arguments: ["direction": arguments.direction])
        throw GameToolStop()
    }
}

struct GameClimbTool: Tool {
    let name: String
    let description: String
    let box: GameCallBox

    @Generable
    struct Arguments {
        @Guide(description: "Which way to climb", .anyOf(["up", "down"]))
        let direction: String
        @Guide(description: "How many rungs", .range(1...9))
        let steps: Int
    }

    func call(arguments: Arguments) async throws -> String {
        box.record(tool: name, arguments: ["direction": arguments.direction, "steps": "\(arguments.steps)"])
        throw GameToolStop()
    }
}

/// The hint engine's tool: one short clue.
struct GameClueTool: Tool {
    let name: String
    let description: String
    let box: GameCallBox

    @Generable
    struct Arguments {
        @Guide(description: "One short, friendly clue, under twelve words")
        let words: String
    }

    func call(arguments: Arguments) async throws -> String {
        box.record(tool: name, arguments: ["words": arguments.words])
        throw GameToolStop()
    }
}

/// unlock, nextLevel and restart: no arguments.
struct GamePlainTool: Tool {
    let name: String
    let description: String
    let box: GameCallBox

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        box.record(tool: name, arguments: [:])
        throw GameToolStop()
    }
}
#endif

/// The game's door to the model. It keeps one session ready (made and prewarmed for the tools of the
/// current state) so that the next request does not wait for it.
@MainActor
final class GameModelEngine {
    static let rulesInstructions = "You control a game by voice. You get one sentence the player said and one line about the game. Call the one tool that does what the sentence asks. If no tool fits, call none and answer none."

    #if canImport(FoundationModels)
    private var ready: (signature: String, session: LanguageModelSession, box: GameCallBox)?
    #endif

    nonisolated static func prompt(words: String, state: GameState) -> String {
        let line = state.oneLine
        return line.isEmpty ? "Sentence: \(words)" : "Game: \(line)\nSentence: \(words)"
    }

    private static func signature(_ instructions: String, _ tools: [GameToolSpec]) -> String {
        instructions + "|" + tools.map { "\($0.name):\($0.description)" }.joined(separator: "|")
    }

    /// Makes and prewarms the session for the next request, if the model is there.
    func prepare(instructions: String, tools: [GameToolSpec]) {
        #if canImport(FoundationModels)
        guard OnDeviceModel.status.isAvailable, !tools.isEmpty else { return }
        let signature = Self.signature(instructions, tools)
        if ready?.signature == signature { return }
        let box = GameCallBox()
        let session = LanguageModelSession(tools: Self.tools(tools, box: box), instructions: instructions)
        session.prewarm()
        ready = (signature, session, box)
        #endif
    }

    /// One request: the sentence and a line of state, the tools of this turn. Ends at the first tool call.
    func ask(role: String, instructions: String, prompt: String, tools: [GameToolSpec]) async -> GameModelTurn {
        var turn = GameModelTurn(role: role, instructions: instructions, prompt: prompt, toolsOffered: tools,
                                 tokens: GameTokenEstimate.estimate(instructions: instructions, prompt: prompt, tools: tools,
                                                                    context: OnDeviceModel.contextSize))
        let started = Date()
        #if canImport(FoundationModels)
        if case .unavailable(let why) = OnDeviceModel.status {
            turn.error = ModelDoorError(kind: "unavailable", words: why, raw: "")
            return turn
        }
        let signature = Self.signature(instructions, tools)
        let session: LanguageModelSession
        let box: GameCallBox
        if let ready, ready.signature == signature {
            session = ready.session
            box = ready.box
            turn.prewarmed = true
            self.ready = nil
        } else {
            box = GameCallBox()
            session = LanguageModelSession(tools: Self.tools(tools, box: box), instructions: instructions)
        }
        do {
            let response = try await session.respond(to: prompt)
            turn.answer = response.content
        } catch {
            if box.call == nil { turn.error = Self.describe(error) }
        }
        if let call = box.call {
            turn.tool = call.tool
            turn.arguments = call.arguments
            turn.firstCallMs = call.at.timeIntervalSince(started) * 1000
        }
        #else
        turn.error = ModelDoorError(kind: "noSDK", words: "This build has no Foundation Models SDK.", raw: "")
        #endif
        turn.totalMs = Date().timeIntervalSince(started) * 1000
        return turn
    }

    #if canImport(FoundationModels)
    private static func tools(_ specs: [GameToolSpec], box: GameCallBox) -> [any Tool] {
        specs.compactMap { spec -> (any Tool)? in
            switch GameToolName(rawValue: spec.name) {
            case .move: return GameMoveTool(name: spec.name, description: spec.description, box: box)
            case .jump: return GameJumpTool(name: spec.name, description: spec.description, box: box)
            case .climb: return GameClimbTool(name: spec.name, description: spec.description, box: box)
            case .unlock, .nextLevel, .restart: return GamePlainTool(name: spec.name, description: spec.description, box: box)
            case .showClue: return GameClueTool(name: spec.name, description: spec.description, box: box)
            case nil: return nil
            }
        }
    }

    private static func describe(_ error: Error) -> ModelDoorError {
        let raw = String(reflecting: error)
        return ModelDoorError.classify(raw: raw, description: error.localizedDescription)
    }
    #endif
}
