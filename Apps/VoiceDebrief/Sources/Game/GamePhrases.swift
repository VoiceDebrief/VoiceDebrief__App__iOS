import Foundation

/// The phrase engine: the code's own fast path, no model. Words in, a command or nothing out, in well
/// under a millisecond, so the model's time can be set beside it.
enum GamePhrases {
    static let numbers: [String: Int] = [
        "one": 1, "once": 1, "two": 2, "twice": 2, "three": 3, "thrice": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    static func parse(_ text: String, kind: GameKind) -> GameCommand? {
        let words = LabTriggerMatcher.words(text)
        guard !words.isEmpty else { return nil }
        let set = Set(words)
        // A refusal or a report is not a command.
        if set.contains("dont") || set.contains("not") || set.contains("never") { return nil }
        if set.contains("thank") || set.contains("thanks") || set.contains("cheers") { return .thanks }
        if set.contains("knock") { return .knock }
        if set.contains("restart") || set.contains("reset") || has(words, ["start", "again"]) || has(words, ["try", "again"]) { return .restart }
        if has(words, ["next", "level"]) || set.contains("continue") || words == ["next"] { return .nextLevel }
        if set.contains("hint") || set.contains("clue") || set.contains("stuck") || set.contains("help") { return .hint }
        if set.contains("unlock") || (set.contains("open") && set.contains("door")) { return .unlock }

        let found = words.enumerated().first { GameDirection.from(word: $0.element) != nil }
        let direction = found.flatMap { GameDirection.from(word: $0.element) }
        let steps = count(words, after: found?.offset)
        let jump = set.contains("jump") || set.contains("hop") || set.contains("leap")
        let climb = set.contains("climb")
        switch kind {
        case .boxes:
            // There is no jumping or climbing among the boxes: a direction is a move.
            if let direction { return .move(direction, steps) }
            return nil
        case .lantern:
            if jump { return .jump(direction) }
            if climb { return .climb(direction ?? .up, steps) }
            if let direction { return .move(direction, steps) }
            return nil
        }
    }

    /// Whether the words hold this run of words, in order and together.
    static func has(_ words: [String], _ run: [String]) -> Bool {
        guard words.count >= run.count else { return false }
        return (0...(words.count - run.count)).contains { Array(words[$0..<($0 + run.count)]) == run }
    }

    /// How many squares: a digit or a number word anywhere, "all the way" for as far as allowed, and
    /// "to", "too" or "for" said just after the direction, which is what the recogniser hears for two and four.
    static func count(_ words: [String], after directionIndex: Int?) -> Int {
        if has(words, ["all", "the", "way"]) || words.contains("far") { return GameRules.maxSteps }
        for word in words {
            if let n = Int(word), n > 0 { return min(n, GameRules.maxSteps) }
            if let n = numbers[word] { return min(n, GameRules.maxSteps) }
        }
        if let index = directionIndex, index + 1 == words.count - 1 {
            switch words[index + 1] {
            case "to", "too": return 2
            case "for": return 4
            default: break
            }
        }
        return 1
    }
}
