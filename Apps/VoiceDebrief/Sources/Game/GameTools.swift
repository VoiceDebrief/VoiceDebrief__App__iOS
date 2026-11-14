import Foundation

/// A tool as the model is offered it for one turn: its name, a description written for this moment,
/// and what its arguments may hold.
struct GameToolSpec: Codable, Equatable, Sendable {
    let name: String
    let description: String
    /// The directions the tool may be given now; empty when it takes none.
    let directions: [String]
    let takesSteps: Bool

    /// Roughly what the framework sends for the arguments, for the token estimate.
    var schemaText: String {
        var parts: [String] = []
        if !directions.isEmpty { parts.append("direction: one of \(directions.joined(separator: ", "))") }
        if takesSteps { parts.append("steps: an integer from 1 to \(GameRules.maxSteps)") }
        return parts.joined(separator: "; ")
    }
}

enum GameToolName: String, CaseIterable, Sendable {
    case move, jump, climb, unlock, nextLevel, restart
}

/// The model's proposal, checked before the rules see it.
enum GameProposalCheck: Equatable, Sendable {
    case ok(GameCommand)
    case refused(String)
}

/// Per-turn tool scoping: only the tools that make sense in this state, each described for now.
/// The easter eggs are never among them.
enum GameToolScope {
    static func tools(for s: GameState) -> [GameToolSpec] {
        switch s.status {
        case .levelWon:
            return [GameToolSpec(name: GameToolName.nextLevel.rawValue, description: "Starts the next level.", directions: [], takesSteps: false)]
        case .won, .lost:
            return [GameToolSpec(name: GameToolName.restart.rawValue, description: "Starts again.", directions: [], takesSteps: false)]
        case .playing:
            break
        }
        var specs: [GameToolSpec] = []
        let open = GameDirection.allCases.filter { direction in
            if s.kind.hasGravity && direction.dx == 0 { return false }
            let tile = s.tile(at: s.player.moved(direction))
            return !tile.isSolid && (tile != .exit || s.exitOpen)
        }.map(\.rawValue)
        if !open.isEmpty {
            let description = s.kind.hasGravity
                ? "Walks left or right. Open now: \(open.joined(separator: ", "))."
                : "Moves the player some squares. Open now: \(open.joined(separator: ", "))."
            specs.append(GameToolSpec(name: GameToolName.move.rawValue, description: description, directions: open, takesSteps: true))
        }
        if s.kind.hasGravity {
            let onLadder = s.tile(at: s.player) == .ladder
            if !onLadder && !s.tile(at: s.player.moved(.up)).isSolid {
                specs.append(GameToolSpec(name: GameToolName.jump.rawValue,
                                          description: "Jumps up and two squares across, over a gap or spikes.",
                                          directions: ["left", "right", "up"], takesSteps: false))
            }
            var climbable: [String] = []
            let above = s.tile(at: s.player.moved(.up))
            if onLadder && !above.isSolid && (above != .exit || s.exitOpen) { climbable.append("up") }
            if s.tile(at: s.player.moved(.down)) == .ladder { climbable.append("down") }
            if !climbable.isEmpty {
                specs.append(GameToolSpec(name: GameToolName.climb.rawValue,
                                          description: "Climbs the ladder. Possible now: \(climbable.joined(separator: ", ")).",
                                          directions: climbable, takesSteps: true))
            }
        }
        let doorNear = GameDirection.allCases.contains { s.tile(at: s.player.moved($0)) == .door }
        if doorNear && s.keys > 0 {
            specs.append(GameToolSpec(name: GameToolName.unlock.rawValue, description: "Unlocks the door next to the player with a key.",
                                      directions: [], takesSteps: false))
        }
        return specs
    }

    /// Checks a tool call against the tools offered this turn and turns it into a command. The rules
    /// then decide whether the command can be carried out.
    static func check(tool: String, arguments: [String: String], offered: [GameToolSpec]) -> GameProposalCheck {
        guard let spec = offered.first(where: { $0.name == tool }), let name = GameToolName(rawValue: tool) else {
            return .refused("The tool \(tool) was not offered this turn.")
        }
        let steps = min(max(Int(arguments["steps"] ?? "") ?? 1, 1), GameRules.maxSteps)
        var direction: GameDirection?
        if !spec.directions.isEmpty {
            let said = (arguments["direction"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            guard spec.directions.contains(said), let d = GameDirection(rawValue: said) else {
                return .refused("The direction \"\(said)\" is not open now.")
            }
            direction = d
        }
        switch name {
        case .move: return direction.map { .ok(.move($0, steps)) } ?? .refused("No direction.")
        case .jump: return .ok(.jump(direction))
        case .climb: return direction.map { .ok(.climb($0, steps)) } ?? .refused("No direction.")
        case .unlock: return .ok(.unlock)
        case .nextLevel: return .ok(.nextLevel)
        case .restart: return .ok(.restart)
        }
    }
}

/// Tokens, estimated at four characters each. Not the model's own count: an estimate, and labelled so.
struct GameTokenEstimate: Codable, Equatable, Sendable {
    var instructions: Int
    var prompt: Int
    var tools: Int
    var context: Int?

    var total: Int { instructions + prompt + tools }

    static func of(_ text: String) -> Int { text.isEmpty ? 0 : max(1, (text.count + 3) / 4) }

    /// Each tool also costs some framing the framework adds; twelve tokens is a guess, and said to be one.
    static let framingPerTool = 12

    static func estimate(instructions: String, prompt: String, tools: [GameToolSpec], context: Int?) -> GameTokenEstimate {
        let toolTokens = tools.reduce(0) { $0 + of($1.name) + of($1.description) + of($1.schemaText) + framingPerTool }
        return GameTokenEstimate(instructions: of(instructions), prompt: of(prompt), tools: toolTokens, context: context)
    }
}

/// What a model request probably cost in energy: its time multiplied by an assumed power. An estimate
/// from an assumption, never a measurement; the screen says so.
enum GameEnergy {
    /// Watts drawn while the on-device model generates: an assumption for an iPhone's Neural Engine and GPU.
    static let assumedWatts = 3.0

    static func milliwattHours(ms: Double, watts: Double = assumedWatts) -> Double {
        watts * (ms / 1000) / 3.6
    }

    static func thermalWords(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
