import Foundation

/// One run of words in a comparison of two texts: in both, only in the first, or only in the second.
struct LabDiffPiece: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case same
        case removed
        case added
    }

    let kind: Kind
    let text: String
}

/// A comparison of two texts, word by word, made by the code. The model proposes a new text; what
/// changed is worked out here, so the screen shows the change as it is and not as it is described.
enum LabDiff {
    /// Above this many pairs of words the comparison is not attempted: the whole of each text is shown.
    static let limit = 1_000_000

    /// A text as words, each keeping the space or line break that follows it.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                inSpace = true
                word.append(character)
            } else {
                if inSpace, !word.isEmpty {
                    out.append(word)
                    word = ""
                }
                inSpace = false
                word.append(character)
            }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    private static func key(_ token: String) -> String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func merged(_ pieces: [LabDiffPiece]) -> [LabDiffPiece] {
        var out: [LabDiffPiece] = []
        for piece in pieces {
            if let last = out.last, last.kind == piece.kind {
                out[out.count - 1] = LabDiffPiece(kind: last.kind, text: last.text + piece.text)
            } else {
                out.append(piece)
            }
        }
        return out
    }

    /// The pieces that turn `before` into `after`: what stays, what goes, what comes in.
    static func words(_ before: String, _ after: String) -> [LabDiffPiece] {
        let a = tokens(before), b = tokens(after)
        guard !a.isEmpty || !b.isEmpty else { return [] }
        guard a.count * b.count <= limit else {
            return [LabDiffPiece(kind: .removed, text: before), LabDiffPiece(kind: .added, text: after)].filter { !$0.text.isEmpty }
        }
        let ka = a.map(key), kb = b.map(key)
        // The longest run of words the two texts share, in order.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = ka[i] == kb[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var pieces: [LabDiffPiece] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if ka[i] == kb[j] {
                pieces.append(LabDiffPiece(kind: .same, text: b[j]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                pieces.append(LabDiffPiece(kind: .removed, text: a[i]))
                i += 1
            } else {
                pieces.append(LabDiffPiece(kind: .added, text: b[j]))
                j += 1
            }
        }
        while i < a.count {
            pieces.append(LabDiffPiece(kind: .removed, text: a[i]))
            i += 1
        }
        while j < b.count {
            pieces.append(LabDiffPiece(kind: .added, text: b[j]))
            j += 1
        }
        return merged(pieces)
    }

    static func count(_ kind: LabDiffPiece.Kind, in pieces: [LabDiffPiece]) -> Int {
        pieces.filter { $0.kind == kind }.reduce(0) { $0 + tokens($1.text).count }
    }
}

enum LabEditPrompt {
    /// Plain, with nothing the model could copy into the text.
    static let instructions = "You edit a piece of text as you are asked. Reply with the edited text only: no introduction, no explanation, and no quotation marks around it. Change only what the request asks for and keep everything else as it is."

    /// Requests kept ready.
    static let presets = ["Make it shorter.", "Make it more formal.", "Turn it into bullet points.", "Fix the spelling of the names.", "Fix the grammar and nothing else."]

    /// The most characters of text sent: the model's context is small and has to hold the answer too.
    static let longest = 4000

    static func prompt(request: String, text: String, names: [String]) -> String {
        var lines = ["Request: " + request.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !names.isEmpty { lines.append("Names that may be meant: " + names.joined(separator: ", ") + ".") }
        lines.append("Text:")
        lines.append(String(text.prefix(longest)))
        return lines.joined(separator: "\n")
    }

    /// The model's reply with the wrapping it sometimes adds taken off: a code fence, or one pair of
    /// quotation marks around the whole of it. Nothing inside is touched.
    static func tidy(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count >= 6 {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("\u{201C}", "\u{201D}")] where text.count >= 2 && text.hasPrefix(open) && text.hasSuffix(close) {
            let inner = String(text.dropFirst().dropLast())
            if !inner.contains(open), !inner.contains(close) { text = inner.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return text
    }
}

/// One proposed edit: the request, the text before, the text the model proposed, the change
/// between them as the code sees it, and what the person decided.
struct LabEditTurn: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable {
        /// Shown, waiting for the person.
        case proposed
        case accepted
        case rejected
        /// The model gave nothing that can be offered.
        case failed
    }

    let number: Int
    let at: Date
    let request: String
    let before: String
    /// The proposed text, tidied. Empty when the model gave none.
    var after = ""
    /// True when a code fence or a pair of quotation marks was taken off the model's reply.
    var tidied = false
    var pieces: [LabDiffPiece] = []
    var state = State.proposed
    var decidedAt: Date?
    var record: ModelDoorRecord?
    var aboutTokensIn: Int?
    /// True when the text was longer than could be sent and only its beginning was.
    var cut = false

    var id: Int { number }
    var wordsBefore: Int { LabDiff.tokens(before).count }
    var wordsAfter: Int { LabDiff.tokens(after).count }
    var wordsRemoved: Int { LabDiff.count(.removed, in: pieces) }
    var wordsAdded: Int { LabDiff.count(.added, in: pieces) }

    /// Takes the proposed text in and works out the change.
    mutating func propose(_ reply: String) {
        let tidy = LabEditPrompt.tidy(reply)
        tidied = tidy != reply.trimmingCharacters(in: .whitespacesAndNewlines)
        after = tidy
        pieces = LabDiff.words(before, tidy)
        state = tidy.isEmpty ? .failed : .proposed
    }

    /// Takes the model's record in: its answer is the proposed text.
    mutating func take(_ record: ModelDoorRecord) {
        self.record = record
        aboutTokensIn = LabLabelWindow.aboutTokens(record.instructions + record.prompt)
        if let answer = record.answer, record.error == nil {
            propose(answer)
        } else {
            state = .failed
        }
    }

    mutating func accept(now: Date = Date()) {
        guard state == .proposed else { return }
        state = .accepted
        decidedAt = now
    }

    mutating func reject(now: Date = Date()) {
        guard state == .proposed else { return }
        state = .rejected
        decidedAt = now
    }

    /// What a person should know before accepting, in plain words.
    var cautions: [String] {
        guard state != .failed else { return [] }
        var out: [String] = []
        if cut { out.append("The text was too long to send whole. Only its first \(LabEditPrompt.longest) characters were edited, and accepting replaces all of it with the edited beginning.") }
        if after == before { out.append("Nothing was changed.") }
        if wordsBefore > 0, wordsAfter > wordsBefore * 2 { out.append("The proposed text is more than twice as long.") }
        if wordsBefore >= 20, wordsAfter * 4 < wordsBefore { out.append("The proposed text is less than a quarter of the length: check that nothing needed has gone.") }
        if tidied { out.append("A code fence or quotation marks around the reply were taken off.") }
        return out
    }

    var notice: String {
        let time = record.map { Timecode.duration(seconds: $0.totalMs / 1000) } ?? "no model"
        if let error = record?.error { return "Edit \(number): \(error.words) (\(time))" }
        if state == .failed { return "Edit \(number): the model gave no text (\(time))" }
        let tokens = aboutTokensIn.map { ", about \($0) tokens in" } ?? ""
        return "Edit \(number): \(time)\(tokens), \(wordsBefore) words to \(wordsAfter), \(wordsRemoved) out and \(wordsAdded) in"
    }
}

/// A whole L07 session, for export.
struct LabEditLog: Codable, Equatable, Sendable {
    var experiment = "L07"
    var device: LabDevice
    var instructions: String
    var turns: [LabEditTurn]

    var json: String { LabRun.json(of: self) }
}
