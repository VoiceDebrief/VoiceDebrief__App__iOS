import Foundation

/// The actions experiment L02 can propose. The raw value is the name of the tool the model sees.
/// In this experiment an action is proposed, shown and confirmed or refused. None is carried out.
enum LabAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case recordFor
    case sendTo
    case finishRecording
    case cancelLast
    case openSection
    case saveToVault
    case findNote

    var id: String { rawValue }

    /// The word used where no action is meant.
    static let none = "none"

    var title: String {
        switch self {
        case .recordFor: return "Record for a time"
        case .sendTo: return "Send to someone"
        case .finishRecording: return "Finish the recording"
        case .cancelLast: return "Cancel the last action"
        case .openSection: return "Open a section"
        case .saveToVault: return "Save to a vault"
        case .findNote: return "Find a note"
        }
    }

    /// The description the model is given.
    var summary: String {
        switch self {
        case .recordFor: return "Starts a recording that stops by itself after a number of minutes."
        case .sendTo: return "Sends the current note to a person, named by the speaker."
        case .finishRecording: return "Stops the recording that is running and keeps it."
        case .cancelLast: return "Cancels the action that was asked for last."
        case .openSection: return "Shows one section of the app."
        case .saveToVault: return "Saves the current note to the vault."
        case .findNote: return "Looks for an earlier note about a subject."
        }
    }

    /// What the one argument holds, or nil when the action takes none.
    var argumentName: String? {
        switch self {
        case .recordFor: return "minutes"
        case .sendTo: return "recipient"
        case .openSection: return "section"
        case .findNote: return "words"
        case .finishRecording, .cancelLast, .saveToVault: return nil
        }
    }

    static func title(for id: String) -> String {
        LabAction(rawValue: id)?.title ?? (id == none ? "No action" : id)
    }
}

/// An action and what it applies to.
struct LabControlProposal: Codable, Equatable, Sendable {
    var action: String
    var argument: String

    var words: String {
        let title = LabAction.title(for: action)
        return argument.isEmpty ? title : "\(title): \(argument)"
    }
}

/// A phrase that proposes an action when it is said. The list is the person's own and can be changed.
struct LabTrigger: Codable, Equatable, Sendable, Identifiable {
    var phrase: String
    var action: String

    var id: String { "\(phrase)|\(action)" }

    /// The fixed phrases the recording already listens for, and a few for the other actions.
    static let defaults: [LabTrigger] =
        VoiceCommand.phrases.map { LabTrigger(phrase: $0, action: LabAction.finishRecording.rawValue) } + [
            LabTrigger(phrase: "record for", action: LabAction.recordFor.rawValue),
            LabTrigger(phrase: "send this to", action: LabAction.sendTo.rawValue),
            LabTrigger(phrase: "send it to", action: LabAction.sendTo.rawValue),
            LabTrigger(phrase: "cancel that", action: LabAction.cancelLast.rawValue),
            LabTrigger(phrase: "open the", action: LabAction.openSection.rawValue),
            LabTrigger(phrase: "go to the", action: LabAction.openSection.rawValue),
            LabTrigger(phrase: "save this to my vault", action: LabAction.saveToVault.rawValue),
            LabTrigger(phrase: "save to the vault", action: LabAction.saveToVault.rawValue),
            LabTrigger(phrase: "find the note about", action: LabAction.findNote.rawValue),
        ]
}

/// The code's own decision engine: fixed phrases, no model. The first of the two engines.
enum LabTriggerMatcher {
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The action the longest matching phrase proposes, with the words said after the phrase as its
    /// argument. A phrase with "not", "never" or "don't" just before it proposes nothing.
    static func match(_ text: String, triggers: [LabTrigger]) -> (trigger: LabTrigger, proposal: LabControlProposal)? {
        let said = words(text)
        guard !said.isEmpty else { return nil }
        let ordered = triggers.sorted { words($0.phrase).count > words($1.phrase).count }
        for trigger in ordered {
            let phrase = words(trigger.phrase)
            guard !phrase.isEmpty, said.count >= phrase.count else { continue }
            for start in 0...(said.count - phrase.count) where Array(said[start..<(start + phrase.count)]) == phrase {
                let before = said[..<start].suffix(2)
                if before.contains("not") || before.contains("never") || before.contains("dont") { return nil }
                let takesArgument = LabAction(rawValue: trigger.action)?.argumentName != nil
                let after = takesArgument ? said[(start + phrase.count)...].joined(separator: " ") : ""
                return (trigger, LabControlProposal(action: trigger.action, argument: after))
            }
        }
        return nil
    }
}

/// Cuts what is heard into the pieces that are each asked about.
enum LabUtterances {
    /// The words that settled since the last piece was taken, and how much of the settled text is now used.
    static func fresh(settled: String, consumed: Int) -> (text: String, consumed: Int)? {
        guard settled.count > consumed else { return nil }
        let text = String(settled.dropFirst(consumed)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !LabTriggerMatcher.words(text).isEmpty else { return nil }
        return (text, settled.count)
    }
}

/// Where one heard sentence stands in the pipeline.
enum LabControlState: String, Codable, Sendable {
    /// The model is being asked.
    case asking
    /// An action is proposed and waits for the person.
    case waiting
    /// The person said do it, or the action is marked automatic.
    case done
    /// The person said not this.
    case notThis
    /// Neither engine proposed an action.
    case nothing
}

/// One sentence taken through experiment L02: what was heard, what each engine proposed, what the
/// person chose, and how long the model took.
struct LabControlEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let heardAt: Date
    let words: String
    /// spoken, typed or test.
    let source: String
    /// For a test sentence: the action it asks for, or none.
    var expected: String?
    /// What the fixed phrases proposed, and which phrase it was.
    var phrase: LabControlProposal?
    var phraseMatched: String?
    /// What the model proposed: the first tool it called.
    var model: LabControlProposal?
    var modelAsked = false
    /// Every tool the model called, in order. More than one is itself a finding.
    var modelCalls: [String] = []
    var record: ModelDoorRecord?
    var state: LabControlState
    /// What the person settled on, after Do it or Edit.
    var chosen: LabControlProposal?
    var edited = false
    var automatic = false
    var decidedAt: Date?

    init(id: String, heardAt: Date, words: String, source: String, expected: String? = nil, triggers: [LabTrigger], askModel: Bool,
         automatic: Set<String> = []) {
        self.id = id
        self.heardAt = heardAt
        self.words = words
        self.source = source
        self.expected = expected
        if let match = LabTriggerMatcher.match(words, triggers: triggers) {
            phrase = match.proposal
            phraseMatched = match.trigger.phrase
        }
        modelAsked = askModel
        state = askModel ? .asking : .nothing
        if !askModel { settle(automatic: automatic, now: heardAt) }
    }

    /// The action the card shows: the model's if it proposed one, else the phrase's.
    var proposal: LabControlProposal? { model ?? phrase }

    var modelMs: Double? { record?.totalMs }

    /// Takes the model's record in, and moves the entry on.
    mutating func receive(_ record: ModelDoorRecord, automatic: Set<String>) {
        self.record = record
        let calls = record.toolCalls.filter { LabAction(rawValue: $0.name) != nil }
        modelCalls = calls.map(\.name)
        if let first = calls.first {
            model = LabControlProposal(action: first.name, argument: first.arguments.values.first ?? "")
        }
        settle(automatic: automatic)
    }

    /// Once both engines have spoken: wait for the person, run by itself if marked so, or rest.
    mutating func settle(automatic: Set<String>, now: Date = Date()) {
        guard let proposal else {
            state = .nothing
            return
        }
        if automatic.contains(proposal.action) {
            state = .done
            chosen = proposal
            self.automatic = true
            decidedAt = now
        } else {
            state = .waiting
        }
    }

    mutating func doIt(now: Date = Date()) {
        guard state == .waiting, let proposal else { return }
        state = .done
        chosen = proposal
        decidedAt = now
    }

    mutating func notThis(now: Date = Date()) {
        guard state == .waiting else { return }
        state = .notThis
        decidedAt = now
    }

    /// The person says what the sentence did ask for: an action, or none.
    mutating func edit(action: String, argument: String, now: Date = Date()) {
        guard state != .asking else { return }
        edited = true
        decidedAt = now
        if action == LabAction.none {
            chosen = nil
            state = proposal == nil ? .nothing : .notThis
        } else {
            chosen = LabControlProposal(action: action, argument: argument)
            state = .done
        }
    }

    /// What is known of the right answer: from the test's expectation, or from what the person did.
    var truth: LabTruth? {
        if let expected { return .action(expected) }
        if edited { return .action(chosen?.action ?? LabAction.none) }
        if automatic { return nil }
        switch state {
        case .done: return chosen.map { .action($0.action) }
        case .notThis: return proposal.map { .not($0.action) }
        case .asking, .waiting, .nothing: return nil
        }
    }

    /// Whether an engine's proposal was right, where that can be told. Only the action is judged,
    /// not its argument.
    func verdict(of proposed: LabControlProposal?) -> Bool? {
        guard let truth else { return nil }
        let action = proposed?.action ?? LabAction.none
        switch truth {
        case .action(let right): return action == right
        case .not(let wrong): return action == wrong ? false : nil
        }
    }

    var modelVerdict: Bool? {
        guard modelAsked, state != .asking, record?.error == nil else { return nil }
        return verdict(of: model)
    }

    var phraseVerdict: Bool? { verdict(of: phrase) }
}

enum LabTruth: Equatable, Sendable {
    /// The sentence asked for this action, or for none.
    case action(String)
    /// It did not ask for this one; what it did ask for is not known.
    case not(String)
}

/// How often each engine proposed the right action, over the sentences that can be judged.
struct LabControlTally: Equatable, Sendable {
    var modelJudged = 0
    var modelRight = 0
    var modelWrongAction = 0
    var modelMissed = 0
    var modelErrors = 0
    var phraseJudged = 0
    var phraseRight = 0
    var modelMeanMs: Double?

    static func of(_ entries: [LabControlEntry]) -> LabControlTally {
        var tally = LabControlTally()
        var times: [Double] = []
        for entry in entries {
            if entry.modelAsked, let record = entry.record {
                if record.error != nil { tally.modelErrors += 1 } else { times.append(record.totalMs) }
            }
            if let right = entry.modelVerdict {
                tally.modelJudged += 1
                if right {
                    tally.modelRight += 1
                } else if entry.model == nil {
                    tally.modelMissed += 1
                } else {
                    tally.modelWrongAction += 1
                }
            }
            if let right = entry.phraseVerdict {
                tally.phraseJudged += 1
                if right { tally.phraseRight += 1 }
            }
        }
        if !times.isEmpty { tally.modelMeanMs = times.reduce(0, +) / Double(times.count) }
        return tally
    }
}

/// A sentence kept ready, with the action it asks for, so the same set can be run on every device.
struct LabControlTest: Equatable, Sendable, Identifiable {
    let words: String
    let expected: String

    var id: String { words }

    static let all: [LabControlTest] = [
        LabControlTest(words: "Record for five minutes.", expected: LabAction.recordFor.rawValue),
        LabControlTest(words: "Send this to Maria.", expected: LabAction.sendTo.rawValue),
        LabControlTest(words: "Stop recording.", expected: LabAction.finishRecording.rawValue),
        LabControlTest(words: "Cancel that.", expected: LabAction.cancelLast.rawValue),
        LabControlTest(words: "Open the library.", expected: LabAction.openSection.rawValue),
        LabControlTest(words: "Save this to my vault.", expected: LabAction.saveToVault.rawValue),
        LabControlTest(words: "Find the note about the boiler.", expected: LabAction.findNote.rawValue),
        // Asked for in words no fixed phrase holds: what a model could add.
        LabControlTest(words: "Could you take me to the settings?", expected: LabAction.openSection.rawValue),
        LabControlTest(words: "That is enough for this one, wrap it up.", expected: LabAction.finishRecording.rawValue),
        LabControlTest(words: "Maria should get a copy of this.", expected: LabAction.sendTo.rawValue),
        // Not instructions: thinking aloud, a report of what someone else did, a refusal.
        LabControlTest(words: "I think the meeting went well and we should plan the next one.", expected: LabAction.none),
        LabControlTest(words: "She said she would send the report to Maria on Friday.", expected: LabAction.none),
        LabControlTest(words: "Do not send it now.", expected: LabAction.none),
        LabControlTest(words: "The vault needs a second remote before we open the office.", expected: LabAction.none),
    ]
}

/// The whole of an L02 session, for export.
struct LabControlLog: Codable, Equatable, Sendable {
    var experiment = "L02"
    var device: LabDevice
    var instructions: String
    var triggers: [LabTrigger]
    var automatic: [String]
    var entries: [LabControlEntry]

    var json: String { LabRun.json(of: self) }
}

enum LabControlDefaults {
    /// The question the model is asked about each sentence. Plain, with nothing it could copy.
    static let instructions = "You are given one sentence that a person said to a voice notes app. Decide whether the sentence is an instruction to the app. If it asks for one of the actions you have tools for, call that one tool, once. If it is not an instruction to the app, call no tool and answer with the one word none. Never call more than one tool."
}
