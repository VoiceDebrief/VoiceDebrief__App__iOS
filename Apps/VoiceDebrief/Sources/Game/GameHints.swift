import Foundation

/// A clue on the board: a square to head for, and at the second level the words to try. Never the
/// whole way.
struct GameHint: Codable, Equatable, Sendable {
    var cell: GamePoint?
    var words: String
    /// 1: the square only. 2: the square and the words.
    var level: Int
    /// code, or model when the model phrased it.
    var source: String
}

/// The hint engine's judgement, in code: when someone looks stuck, and what to show.
enum GameHints {
    /// Wrong or useless commands in a row before a clue.
    static let wrongBeforeHint = 2
    /// Moves without finding anything before a clue.
    static let movesBeforeHint = 8

    /// The level of clue to show now, or nil. A clue already showing goes up a level when it did not help.
    static func level(wrongStreak: Int, movesSinceProgress: Int, asked: Bool, showing: GameHint?) -> Int? {
        let stuck = asked || wrongStreak >= wrongBeforeHint || movesSinceProgress >= movesBeforeHint
        guard stuck else { return nil }
        guard let showing else { return 1 }
        return min(showing.level + 1, 2)
    }

    static func make(_ state: GameState, level: Int) -> GameHint? {
        guard state.status == .playing else {
            switch state.status {
            case .levelWon: return GameHint(cell: nil, words: "Say \u{201C}next level\u{201D}.", level: 2, source: "code")
            case .won, .lost: return GameHint(cell: nil, words: "Say \u{201C}restart\u{201D}.", level: 2, source: "code")
            case .playing: return nil
            }
        }
        guard let plan = GamePlanner.plan(state), let first = GamePlanner.compress(plan).first else {
            return GameHint(cell: nil, words: "No way through from here without losing a life. Say \u{201C}restart\u{201D}.", level: 2, source: "code")
        }
        let cell = GamePlanner.target(state, plan: plan)
        if level <= 1 {
            return GameHint(cell: cell, words: "Head for the glowing square.", level: 1, source: "code")
        }
        return GameHint(cell: cell, words: "Try saying \u{201C}\(first.words)\u{201D}.", level: 2, source: "code")
    }

    /// Events that count as progress: something found or opened.
    static func isProgress(_ events: [GameEvent]) -> Bool {
        let progress: Set<GameEvent> = [.gold, .key, .unlocked, .levelWon, .gameWon, .nextLevel, .restarted, .egg]
        return events.contains { progress.contains($0) }
    }
}
