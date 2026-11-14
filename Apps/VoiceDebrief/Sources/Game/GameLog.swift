import Foundation

/// How a sentence is decided.
enum GameEngineMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The phrases only: the code's fast path.
    case phrases
    /// The model only, with the tools of this turn.
    case model
    /// The phrases first; the model when they find nothing.
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phrases: return "Phrases"
        case .model: return "Model"
        case .both: return "Both"
        }
    }
}

/// One sentence through the game: what was heard, what each engine made of it, what happened, and
/// the time from the end of speaking to the new state.
struct GameLogEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let game: GameKind
    let level: Int
    var words: String
    /// spoken, typed or player.
    let source: String
    /// The end of speaking: the last change to the live words, the moment the voice player's speech
    /// finished, or the press of return.
    let endedAt: Date
    /// When the words settled, for spoken words.
    var settledAt: Date?
    /// Acted on before the words settled.
    var early = false
    /// What the phrases made of it, and how long that took.
    var phrase: String?
    var phraseMs: Double = 0
    /// The model's request, if it was asked.
    var model: GameModelTurn?
    /// The model was asked only to compare: the phrases had acted.
    var shadow = false
    /// What the model proposed, checked: the command, or why it was refused.
    var modelCommand: String?
    var modelRefusal: String?
    /// phrases, model or none.
    var engine = "none"
    var command: String?
    var accepted: Bool?
    var outcome: String?
    var appliedAt: Date?
    var thermal: String

    /// From the end of speaking to the new state.
    var totalMs: Double? { appliedAt.map { $0.timeIntervalSince(endedAt) * 1000 } }
    /// From the end of speaking to the words settling.
    var settleMs: Double? { settledAt.map { $0.timeIntervalSince(endedAt) * 1000 } }
}

/// The figures over a log, by the engine that acted.
struct GameStats: Equatable, Sendable {
    var commands = 0
    var phraseActed = 0
    var modelActed = 0
    var notUnderstood = 0
    var phraseMeanMs: Double?
    var modelMeanMs: Double?
    /// Over every model request, acting or in the shadow.
    var modelRequests = 0
    var modelFirstCallMeanMs: Double?
    var modelEnergyMilliwattHours: Double = 0
    var tokensMean: Int?

    static func of(_ entries: [GameLogEntry]) -> GameStats {
        var stats = GameStats()
        var phraseTimes: [Double] = []
        var modelTimes: [Double] = []
        var firstCalls: [Double] = []
        var tokens: [Int] = []
        for entry in entries {
            stats.commands += 1
            switch entry.engine {
            case "phrases":
                stats.phraseActed += 1
                if let ms = entry.totalMs { phraseTimes.append(ms) }
            case "model":
                stats.modelActed += 1
                if let ms = entry.totalMs { modelTimes.append(ms) }
            default:
                if entry.model?.tool == nil && entry.phrase == nil { stats.notUnderstood += 1 }
            }
            if let turn = entry.model {
                stats.modelRequests += 1
                stats.modelEnergyMilliwattHours += turn.energyMilliwattHours
                tokens.append(turn.tokens.total)
                if let ms = turn.firstCallMs { firstCalls.append(ms) }
            }
        }
        stats.phraseMeanMs = mean(phraseTimes)
        stats.modelMeanMs = mean(modelTimes)
        stats.modelFirstCallMeanMs = mean(firstCalls)
        stats.tokensMean = tokens.isEmpty ? nil : tokens.reduce(0, +) / tokens.count
        return stats
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// The whole of a play session, for export.
struct GameLog: Codable, Equatable, Sendable {
    var experiment = "L03"
    var device: LabDevice
    var rulesInstructions: String
    /// The assumptions the estimates rest on, in words.
    var assumptions: [String]
    var entries: [GameLogEntry]

    var json: String { LabRun.json(of: self) }

    static let assumptionWords = [
        "Tokens are estimated at four characters each, with \(GameTokenEstimate.framingPerTool) more for each tool's framing. Not the model's own count.",
        "Energy is the model's time multiplied by an assumed \(GameEnergy.assumedWatts) W. An estimate, not a measurement.",
        "The end of speaking is the last change to the live words (spoken), the end of the voice player's speech (player), or the press of return (typed).",
    ]
}

/// Words for times and energy on the screen.
enum GameWords {
    static func ms(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value >= 10_000 ? String(format: "%.1f s", value / 1000) : "\(Int(value.rounded())) ms"
    }

    static func energy(_ mWh: Double) -> String {
        mWh < 0.01 ? String(format: "%.3f mWh", mWh) : String(format: "%.2f mWh", mWh)
    }
}
