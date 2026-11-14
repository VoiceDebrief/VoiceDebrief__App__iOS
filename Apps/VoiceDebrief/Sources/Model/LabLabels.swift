import Foundation

/// What a label holds: a person, free words, or one of a fixed few.
enum LabLabelKind: Equatable, Sendable {
    case person
    case text
    case choice([String])
}

/// One label experiment L04 can fill in while a note is being spoken. The model has one tool for
/// each label; `tool` is that tool's name.
struct LabLabelField: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// The description the model is given for the label's tool.
    let summary: String
    let kind: LabLabelKind
    /// The four that are always on. The others are chosen from the list.
    let always: Bool

    var tool: String { "set" + id.prefix(1).uppercased() + id.dropFirst() }

    static let urgencies = ["low", "normal", "high"]
    static let kinds = ["memo", "idea", "task", "question", "update"]

    static let all: [LabLabelField] = [
        LabLabelField(id: "forWhom", title: "For", summary: "Says who the note is for: one person or agent, by name.", kind: .person, always: true),
        LabLabelField(id: "topic", title: "Topic", summary: "Says what the note is about, in a few words.", kind: .text, always: true),
        LabLabelField(id: "title", title: "Title", summary: "Gives the note a short title, of six words at most.", kind: .text, always: true),
        LabLabelField(id: "urgency", title: "Urgency", summary: "Says how urgent the note is.", kind: .choice(urgencies), always: true),
        LabLabelField(id: "kind", title: "Kind", summary: "Says what kind of note it is.", kind: .choice(kinds), always: false),
        LabLabelField(id: "nextAction", title: "Next action", summary: "Says the one thing to do next, if the note asks for something to be done.", kind: .text, always: false),
        LabLabelField(id: "people", title: "People mentioned", summary: "Lists the people the note mentions by name.", kind: .text, always: false),
        LabLabelField(id: "project", title: "Project", summary: "Names the project or piece of work the note belongs to.", kind: .text, always: false),
    ]

    /// The optional labels that are on until the person says otherwise.
    static let firstChoice: Set<String> = ["kind", "nextAction"]

    static func find(_ id: String) -> LabLabelField? { all.first { $0.id == id } }
    static func find(tool: String) -> LabLabelField? { all.first { $0.tool == tool } }

    /// The labels in use: the four that always are, and the chosen ones, in the list's order.
    static func inUse(_ chosen: Set<String>) -> [LabLabelField] { all.filter { $0.always || chosen.contains($0.id) } }
}

/// Someone a note can be for: a contact or an agent, with what is needed to draw their face.
struct LabLabelCandidate: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// person, conductor, session or subagent.
    let kind: String
}

enum LabLabelMatch {
    private static let small: Set<String> = ["the", "a", "an", "my", "our", "for", "to", "mr", "mrs", "ms", "dr"]

    static func words(_ text: String) -> [String] {
        LabTriggerMatcher.words(text).filter { !small.contains($0) }
    }

    /// The one candidate a spoken name means: the same words, or else the only candidate whose name
    /// holds every word said. Two candidates that fit are no match: the code does not guess.
    static func person(_ spoken: String, among candidates: [LabLabelCandidate]) -> LabLabelCandidate? {
        let said = words(spoken)
        guard !said.isEmpty else { return nil }
        if let exact = candidates.first(where: { words($0.name) == said }) { return exact }
        let holding = candidates.filter { candidate in
            let name = words(candidate.name)
            return said.allSatisfy { word in name.contains { $0.hasPrefix(word) } }
        }
        return holding.count == 1 ? holding[0] : nil
    }
}

/// A label's value, and who gave it.
struct LabLabelValue: Codable, Equatable, Sendable {
    var text: String
    /// model, voice or hand.
    var source: String
    /// The loop that set it, when the model did.
    var loop: Int?
    /// For the label that names a person: the contact or agent the words were matched to, if one was.
    var matched: LabLabelCandidate?
}

/// What became of one value offered for a label.
enum LabLabelOutcome: String, Codable, Sendable {
    /// The label now holds it.
    case changed
    /// The label already held it.
    case same
    /// The person set this label by voice or by hand, and that stands.
    case pinned
    /// Not one of the label's choices, empty, or a label that is not in use.
    case rejected
}

/// The labels of the note being spoken. The code owns this: the model proposes a value through a
/// tool, the board decides. A value the person gave is pinned and no proposal moves it.
struct LabLabelBoard: Codable, Equatable, Sendable {
    private(set) var values: [String: LabLabelValue] = [:]
    private(set) var pinned: Set<String> = []

    static let longest = 80

    static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(longest))
    }

    /// The value as the label keeps it, or nil when the label cannot hold it.
    static func fitted(_ text: String, to field: LabLabelField) -> String? {
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return nil }
        if case .choice(let options) = field.kind {
            let lower = cleaned.lowercased()
            return options.contains(lower) ? lower : nil
        }
        return cleaned
    }

    private func value(_ text: String, for field: LabLabelField, source: String, loop: Int?, candidates: [LabLabelCandidate]) -> LabLabelValue {
        let matched = field.kind == .person ? LabLabelMatch.person(text, among: candidates) : nil
        return LabLabelValue(text: matched?.name ?? text, source: source, loop: loop, matched: matched)
    }

    /// A value from the model. It never moves a pinned label.
    mutating func propose(_ text: String, for fieldId: String, loop: Int, inUse: [LabLabelField],
                          candidates: [LabLabelCandidate]) -> LabLabelOutcome {
        guard let field = inUse.first(where: { $0.id == fieldId }), let fitted = LabLabelBoard.fitted(text, to: field) else { return .rejected }
        if pinned.contains(fieldId) { return .pinned }
        let new = value(fitted, for: field, source: "model", loop: loop, candidates: candidates)
        if values[fieldId]?.text.lowercased() == new.text.lowercased() { return .same }
        values[fieldId] = new
        return .changed
    }

    /// A value the person gave, by voice or by hand. It is kept and pinned.
    @discardableResult
    mutating func override(_ text: String, for fieldId: String, source: String = "voice", candidates: [LabLabelCandidate]) -> Bool {
        guard let field = LabLabelField.find(fieldId), let fitted = LabLabelBoard.fitted(text, to: field) else { return false }
        values[fieldId] = value(fitted, for: field, source: source, loop: nil, candidates: candidates)
        pinned.insert(fieldId)
        return true
    }

    /// Lets the model fill a label again. What it holds stays until something replaces it.
    mutating func unpin(_ fieldId: String) { pinned.remove(fieldId) }

    func isPinned(_ fieldId: String) -> Bool { pinned.contains(fieldId) }

    /// For when the labels travel with a note: who it is for, if a contact or agent was matched, and its title.
    var recipient: LabLabelCandidate? { values["forWhom"]?.matched }
    var title: String? { values["title"]?.text }
}

/// The person setting a label by saying so, found by the code, not by the model.
enum LabLabelOverrides {
    private static let forWhom = ["this is a memo for", "this is a note for", "this is a message for", "this one is for",
                                  "this is for", "it is for", "memo for", "note for"]

    /// A sentence as words, each with its plain form for matching and its own form for keeping.
    private static func tokens(_ text: String) -> [(plain: String, raw: String)] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { piece in
            let plain = LabTriggerMatcher.words(String(piece)).joined()
            return plain.isEmpty ? nil : (plain, String(piece))
        }
    }

    private static func after(_ phrase: String, in tokens: [(plain: String, raw: String)]) -> String? {
        let wanted = phrase.split(separator: " ").map(String.init)
        guard !wanted.isEmpty, tokens.count > wanted.count else { return nil }
        for start in 0...(tokens.count - wanted.count) where tokens[start..<(start + wanted.count)].map(\.plain) == wanted {
            let rest = tokens[(start + wanted.count)...].map(\.raw).joined(separator: " ")
            let value = LabLabelBoard.clean(rest)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The labels a sentence sets: "this is a memo for the website conductor", "no, the topic is X",
    /// "the title is X", "this is urgent". The value is everything after the phrase.
    static func detect(_ sentence: String, inUse: [LabLabelField]) -> [(field: String, value: String)] {
        let said = tokens(sentence)
        var found: [(field: String, value: String)] = []
        for field in inUse {
            if field.id == "forWhom" {
                if let value = forWhom.lazy.compactMap({ after($0, in: said) }).first { found.append((field.id, value)) }
                continue
            }
            let name = field.title.lowercased()
            if let value = after("the \(name) is", in: said) ?? after("\(name) is", in: said) {
                if LabLabelBoard.fitted(value, to: field) != nil { found.append((field.id, value)) }
                continue
            }
            if field.id == "urgency" {
                let plain = said.map(\.plain)
                if let at = plain.firstIndex(of: "urgent") {
                    let before = plain[..<at].suffix(2)
                    found.append((field.id, before.contains("not") || before.contains("isnt") ? "low" : "high"))
                }
            }
        }
        return found
    }
}

/// How much of what has been said is sent to the model on each loop.
enum LabLabelWindow {
    /// A token is taken as four characters: a rule of thumb, not a count.
    static let charactersPerToken = 4

    static func aboutTokens(_ text: String) -> Int { (text.count + charactersPerToken - 1) / charactersPerToken }

    /// The last `tokens` tokens' worth of the words, starting at a whole word; all of them when `tokens` is 0.
    static func take(_ transcript: String, tokens: Int) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = tokens * charactersPerToken
        guard tokens > 0, text.count > limit else { return text }
        let tail = text.suffix(limit)
        guard let space = tail.firstIndex(where: { $0.isWhitespace }) else { return String(tail) }
        return String(tail[space...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LabLabelPrompt {
    /// Plain, with nothing the model could copy into a label.
    static let instructions = "You read the words of a voice note that is still being recorded, and you fill in labels for it. For each label that the words make clear, call that label's tool once, with a short value. Do not call a tool for a label the words do not make clear. Do not answer in text."

    /// The state the code hands the model for one loop: the labels as they stand, who the note could
    /// be for, and the window of words.
    static func prompt(board: LabLabelBoard, inUse: [LabLabelField], candidates: [LabLabelCandidate], window: String) -> String {
        var lines: [String] = []
        let held = inUse.compactMap { field in board.values[field.id].map { "\(field.title): \($0.text)" } }
        if !held.isEmpty { lines.append("Labels so far. " + held.joined(separator: ". ") + ".") }
        if !candidates.isEmpty { lines.append("People and agents the note can be for: " + candidates.map(\.name).joined(separator: ", ") + ".") }
        lines.append("Words of the note so far:")
        lines.append(window)
        return lines.joined(separator: "\n")
    }
}

/// One value the model offered in a loop, and what the board did with it.
struct LabLabelProposal: Codable, Equatable, Sendable {
    let field: String
    let value: String
    let outcome: LabLabelOutcome
    /// How long after the request began this call arrived.
    let atMs: Double?
}

/// One loop: what was sent, what came back, how long it took, and which labels changed.
struct LabLabelLoop: Codable, Equatable, Sendable, Identifiable {
    let number: Int
    let at: Date
    /// The window asked for, in tokens; 0 means everything said so far.
    let windowTokens: Int
    let windowCharacters: Int
    let transcriptCharacters: Int
    /// Instructions, prompt and tool descriptions together, at four characters a token.
    let aboutTokensIn: Int
    let proposals: [LabLabelProposal]
    let record: ModelDoorRecord

    var id: Int { number }
    var totalMs: Double { record.totalMs }
    var firstCallMs: Double? { proposals.compactMap(\.atMs).min() }
    var changed: [String] { proposals.filter { $0.outcome == .changed }.map(\.field) }

    /// The small notice shown after every loop.
    var notice: String {
        let all = Timecode.duration(seconds: totalMs / 1000)
        if let error = record.error { return "Loop \(number): \(error.words) (\(all))" }
        let first = firstCallMs.map { Timecode.duration(seconds: $0 / 1000) + " to the first label, " } ?? "no label offered, "
        let titles = changed.map { LabLabelField.find($0)?.title ?? $0 }
        let moved = titles.isEmpty ? "nothing changed" : "changed: " + titles.joined(separator: ", ")
        return "Loop \(number): \(first)\(all) in all, about \(aboutTokensIn) tokens in, \(moved)"
    }

    /// Applies a model's record to the board and makes the loop's entry.
    static func apply(_ record: ModelDoorRecord, to board: inout LabLabelBoard, number: Int, windowTokens: Int, window: String,
                      transcript: String, inUse: [LabLabelField], candidates: [LabLabelCandidate]) -> LabLabelLoop {
        var proposals: [LabLabelProposal] = []
        for call in record.toolCalls {
            guard let field = LabLabelField.find(tool: call.name) else { continue }
            let value = call.arguments["value"] ?? ""
            let outcome = board.propose(value, for: field.id, loop: number, inUse: inUse, candidates: candidates)
            proposals.append(LabLabelProposal(field: field.id, value: value, outcome: outcome, atMs: call.atMs))
        }
        let sent = record.instructions + record.prompt + record.toolsOffered.map { $0.name + $0.description }.joined()
        return LabLabelLoop(number: number, at: record.startedAt, windowTokens: windowTokens, windowCharacters: window.count,
                            transcriptCharacters: transcript.count, aboutTokensIn: LabLabelWindow.aboutTokens(sent),
                            proposals: proposals, record: record)
    }
}

/// A whole L04 session, for export.
struct LabLabelLog: Codable, Equatable, Sendable {
    var experiment = "L04"
    var device: LabDevice
    var instructions: String
    var labels: [String]
    var secondsBetweenLoops: Int
    var windowTokens: Int
    var board: LabLabelBoard
    var overrides: [LabLabelOverrideEntry]
    var loops: [LabLabelLoop]

    var json: String { LabRun.json(of: self) }
}

/// A label the person set by saying so, with the sentence it was found in.
struct LabLabelOverrideEntry: Codable, Equatable, Sendable {
    let at: Date
    let field: String
    let value: String
    let sentence: String
}
