import Foundation

/// An experiment (issue 024): the note rewritten as clear sentences, a passage at a time, with the
/// places the model could not follow turned into questions. The transcript as heard is never replaced.

/// A word the speaker uses and the ways the speech model has been known to hear it.
struct GlossaryTerm: Codable, Equatable, Sendable, Identifiable {
    var word: String
    var heardAs: [String]

    var id: String { word.lowercased() }
}

enum Glossary {
    /// "vote, volt" -> ["vote", "volt"]: trimmed, no empties, no repeats, never the word itself.
    static func variants(from text: String, word: String = "") -> [String] {
        var seen: Set<String> = [word.trimmingCharacters(in: .whitespaces).lowercased()]
        var out: [String] = []
        for piece in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline }) {
            let variant = piece.trimmingCharacters(in: .whitespaces)
            guard !variant.isEmpty, seen.insert(variant.lowercased()).inserted else { continue }
            out.append(variant)
        }
        return out
    }

    /// Adds a term, or the new variants of one already there. The word keeps its first spelling.
    static func adding(_ word: String, heardAs: [String], to terms: [GlossaryTerm]) -> [GlossaryTerm] {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return terms }
        var terms = terms
        let cleaned = variants(from: heardAs.joined(separator: ","), word: word)
        if let index = terms.firstIndex(where: { $0.id == word.lowercased() }) {
            terms[index].heardAs = variants(from: (terms[index].heardAs + cleaned).joined(separator: ","), word: word)
        } else {
            terms.append(GlossaryTerm(word: word, heardAs: cleaned))
        }
        return terms
    }

    /// The glossary as the model reads it, one term a line. Empty when there are no terms.
    static func promptLines(_ terms: [GlossaryTerm]) -> String {
        terms.map { term in
            term.heardAs.isEmpty ? "- \(term.word)"
                                 : "- \(term.word) (sometimes heard as: \(term.heardAs.joined(separator: ", ")))"
        }.joined(separator: "\n")
    }
}

/// Something the model could not make sense of, and what the speaker said it was.
struct CleanQuestion: Codable, Equatable, Sendable, Identifiable {
    var phrase: String
    var question: String
    var answer: String?

    var id: String { phrase + "|" + question }
}

/// A stretch of the transcript and what was made of it.
struct CleanPassage: Codable, Equatable, Sendable, Identifiable {
    let startMs: Int
    let endMs: Int
    let heard: String
    var clean: String?
    var questions: [CleanQuestion]
    var seconds: Double
    /// Why there is no clean text for this passage, in plain words.
    var problem: String?

    var id: Int { startMs }

    /// True when the rewrite is so much shorter than what was heard that it probably left things out.
    var looksCut: Bool {
        guard let clean else { return false }
        let before = WordDiff.words(heard).count, after = WordDiff.words(clean).count
        return before >= 20 && after * 2 < before
    }
}

struct CleanText: Codable, Equatable, Sendable {
    var passages: [CleanPassage]
    var madeAt: Date
    /// The glossary words the model was given, so a result can be read against what it knew.
    var glossaryWords: [String]
    var contextSize: Int?
    /// False while passages are still being written.
    var finished: Bool

    var seconds: Double { passages.reduce(0) { $0 + $1.seconds } }
    var openQuestions: Int { passages.reduce(0) { $0 + $1.questions.filter { $0.answer == nil }.count } }

    /// The clean passages as one text; a passage with no rewrite keeps what was heard.
    var text: String { passages.map { $0.clean ?? $0.heard }.joined(separator: "\n\n") }
}

enum Passages {
    /// Small enough that a passage, the glossary, the instructions and the answer fit a 4,096-token
    /// model with room to spare, and that one bad passage costs little.
    static let targetWords = 110

    /// Transcript lines gathered into passages of about `targetWords`. A line is never split, so a
    /// very long line is a passage by itself.
    static func split(_ lines: [TranscriptLine], targetWords: Int = Passages.targetWords) -> [CleanPassage] {
        var out: [CleanPassage] = []
        var group: [TranscriptLine] = []
        var count = 0
        func close() {
            guard let first = group.first, let last = group.last else { return }
            out.append(CleanPassage(startMs: first.startMs, endMs: last.endMs,
                                    heard: group.map(\.text).joined(separator: " "),
                                    clean: nil, questions: [], seconds: 0, problem: nil))
            group = []
            count = 0
        }
        for line in lines {
            let words = WordDiff.words(line.text).count
            if words == 0 { continue }
            if count > 0, count + words > targetWords { close() }
            group.append(line)
            count += words
        }
        close()
        return out
    }
}

enum CleanPrompt {
    /// One passage, one question. No quotation marks around examples: a small model copies them.
    static func make(heard: String, glossary: [GlossaryTerm], localeId: String) -> String {
        let language = Locale(identifier: "en").localizedString(forIdentifier: localeId) ?? localeId
        var prompt = """
            Below is a passage from my own voice note, as a speech recogniser heard it. It contains false starts, repeated words, filler and words that were heard wrongly.

            Rewrite the passage as clear, complete sentences in \(language).
            - Keep everything I said and keep it in the same order. Do not summarise. Do not add anything.
            - Keep it in the first person, as I said it.
            - Remove filler, false starts and repetitions.
            - Where a word makes no sense and another word that sounds like it would, use the word I must have meant.

            """
        let terms = Glossary.promptLines(glossary)
        if !terms.isEmpty {
            prompt += """

                These are words I use. If the passage has something that sounds like one of them where it would make sense, write the word from this list:
                \(terms)

                """
        }
        prompt += """

            Then list the phrases you could not make sense of, at most three, each with the exact words from the passage and one short question to ask me. If everything was clear, list none.

            Passage:
            \(heard)
            """
        return prompt
    }
}

/// What changed between the passage as heard and as rewritten, word by word.
enum WordDiff {
    enum Kind: String, Sendable { case same, removed, added }
    struct Segment: Equatable, Sendable {
        let kind: Kind
        var text: String
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Words compare without case or the punctuation around them, so "Vault," matches "vault".
    static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Runs of kept, removed and added words, in reading order: removed words before the added ones
    /// that took their place.
    static func segments(heard: String, clean: String) -> [Segment] {
        let a = words(heard), b = words(clean)
        let ka = a.map(key), kb = b.map(key)
        // Longest common subsequence, by table. Passages are about a hundred words.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = ka[i] == kb[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var out: [Segment] = []
        func push(_ kind: Kind, _ word: String) {
            if let last = out.indices.last, out[last].kind == kind {
                out[last].text += " " + word
            } else {
                out.append(Segment(kind: kind, text: word))
            }
        }
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if ka[i] == kb[j] {
                push(.same, b[j]); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                push(.removed, a[i]); i += 1
            } else {
                push(.added, b[j]); j += 1
            }
        }
        while i < a.count { push(.removed, a[i]); i += 1 }
        while j < b.count { push(.added, b[j]); j += 1 }
        return out
    }
}
