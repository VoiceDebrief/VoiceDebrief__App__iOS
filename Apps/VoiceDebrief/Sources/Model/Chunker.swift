import Foundation

/// Splits a transcript into pieces the on-device model can read in one go. The model's context is
/// small (4,096 tokens on iOS 26, 8,192 on newer devices under iOS 27), so a long voice note has to
/// be read in sections and the sections merged.
enum Chunker {
    /// Tokens kept back for the instructions and for the model's answer.
    static let reservedTokens = 1300
    /// A cautious figure: English runs nearer four characters a token, Portuguese nearer three.
    static let charactersPerToken = 3

    /// How many characters of transcript fit in one request for a model of this context size.
    static func characterBudget(contextSize: Int) -> Int {
        max(1500, (contextSize - reservedTokens) * charactersPerToken)
    }

    /// Consecutive lines grouped so that each group's timed text fits the budget. A single line
    /// longer than the budget gets a group of its own rather than being cut.
    static func chunks(_ lines: [TranscriptLine], budget: Int) -> [[TranscriptLine]] {
        var out: [[TranscriptLine]] = []
        var current: [TranscriptLine] = []
        var size = 0
        for line in lines {
            let cost = line.text.count + 9      // "[mm:ss] " and the newline
            if !current.isEmpty && size + cost > budget {
                out.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += cost
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
