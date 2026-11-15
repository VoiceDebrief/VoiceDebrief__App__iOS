import Foundation

/// The app's own data as experiments L05 and L06 see it: copied out before a question is asked,
/// so answering never touches the library, the contacts or the agents report.
struct LabWorld: Equatable, Sendable {
    struct Send: Equatable, Sendable {
        let to: String
        let at: Date
    }

    struct NoteItem: Equatable, Sendable {
        let id: String
        let createdAt: Date
        let title: String
        let transcript: String
        /// The bullets under Actions in the note's debrief.
        let actions: [String]
        let sends: [Send]
        /// A send asked for and not yet done, and why the last one did not go.
        var pendingTo: String?
        var sendProblem: String?
    }

    struct AgentItem: Equatable, Sendable {
        let id: String
        let name: String
        let status: String
        let doing: String
        let waitingFor: String?
    }

    struct MessageItem: Equatable, Sendable {
        let id: String
        /// The name of the agent the conversation is with.
        let agent: String
        let fromYou: Bool
        let at: Date
        let text: String
        /// What it answers: the start of your note, in your words.
        let quote: String?
    }

    var now: Date
    var calendar: Calendar = .current
    var notes: [NoteItem] = []
    var contacts: [String] = []
    var agents: [AgentItem] = []
    var messages: [MessageItem] = []

    /// Everyone a question can name: contacts first, then agents not already among them.
    var people: [String] {
        contacts + agents.map(\.name).filter { !contacts.contains($0) }
    }

    /// The bullets under the Actions heading of a debrief, leaving out the line that says there are none.
    static func actions(in debrief: String?) -> [String] {
        guard let debrief else { return [] }
        var inActions = false
        var found: [String] = []
        for block in DebriefMarkdown.blocks(debrief) {
            switch block {
            case .heading(let text): inActions = text.lowercased() == "actions"
            case .bullet(let text):
                if inActions, !text.lowercased().hasPrefix("none mentioned"), !text.isEmpty { found.append(plain(text)) }
            case .paragraph: break
            }
        }
        return found
    }

    /// An action as a sentence to be read or said: the square brackets that say whose it is are
    /// dropped when it is the person's own, and become a name and a colon when it is someone else's.
    static func plain(_ action: String) -> String {
        guard action.hasPrefix("["), let close = action.firstIndex(of: "]") else { return action }
        let who = action[action.index(after: action.startIndex)..<close].trimmingCharacters(in: .whitespaces)
        let rest = action[action.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return action }
        return who.lowercased() == "me" || who.isEmpty ? rest : "\(who): \(rest)"
    }

    /// Whether a reply's quote is the start of this note: the first six words agree.
    static func quote(_ quote: String?, isStartOf transcript: String) -> Bool {
        let quoted = LabTriggerMatcher.words(quote ?? "").prefix(6)
        guard quoted.count >= 3 else { return false }
        return Array(LabTriggerMatcher.words(transcript).prefix(quoted.count)) == Array(quoted)
    }

    /// A time said the way a person would: today at 14:05, yesterday at 09:30, 12 November at 18:00.
    func said(_ date: Date) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_GB")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return "today at " + time.string(from: date) }
        if days == 1 { return "yesterday at " + time.string(from: date) }
        time.dateFormat = "d MMMM 'at' HH:mm"
        return time.string(from: date)
    }
}

/// The kinds of thing a question can be about. The raw value is the name of the tool the model
/// calls to say so.
enum LabAskKind: String, Codable, CaseIterable, Sendable {
    case tasks = "findTasks"
    case notes = "findNotes"
    case sent = "findSent"
    case person = "findPerson"
    case decisions = "findDecisions"

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .notes: return "Notes"
        case .sent: return "What was sent"
        case .person: return "A person"
        case .decisions: return "Decisions waiting"
        }
    }

    /// The description the model is given.
    var summary: String {
        switch self {
        case .tasks: return "For a question about tasks, actions or things to do."
        case .notes: return "For a question about voice notes that were recorded."
        case .sent: return "For a question about a note or memo that was sent to someone, and what happened to it."
        case .person: return "For a question about one person or agent: what they said or what was sent to them."
        case .decisions: return "For a question about decisions, or about what is waiting for the person asking."
        }
    }
}

/// When a question is about.
enum LabWhen: String, Codable, CaseIterable, Sendable {
    case any = "any time"
    case today
    case yesterday
    case week = "this week"

    func holds(_ date: Date, in world: LabWorld) -> Bool {
        let days = world.calendar.dateComponents([.day], from: world.calendar.startOfDay(for: date),
                                                 to: world.calendar.startOfDay(for: world.now)).day ?? 0
        switch self {
        case .any: return true
        case .today: return days == 0
        case .yesterday: return days == 1
        case .week: return days >= 0 && days < 7
        }
    }
}

/// A question, once it is known what kind of thing it asks for and with which limits.
struct LabQuestion: Codable, Equatable, Sendable {
    var kind: LabAskKind
    /// The subject, as a few plain words, or empty.
    var about = ""
    /// The full name of a contact or agent, or empty.
    var person = ""
    var when = LabWhen.any

    /// The limits in words, for the answer: about the boiler, from yesterday.
    var scope: String {
        var parts: [String] = []
        if !about.isEmpty { parts.append("about \(about)") }
        if !person.isEmpty, kind != .person { parts.append(kind == .sent ? "to \(person)" : "for \(person)") }
        if when != .any { parts.append("from \(when.rawValue)") }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    var words: String { kind.title + (scope.isEmpty ? "" : "," + scope) }
}

/// The code's own way of telling what a question asks for: word lists, no model. The second engine,
/// and the one that answers when the model is not there or calls no tool.
enum LabAskRules {
    private static let decisions: Set<String> = ["decision", "decisions", "decide", "waiting", "blocked", "approve", "approval"]
    private static let tasks: Set<String> = ["task", "tasks", "todo", "todos", "actions", "action"]
    private static let sent: Set<String> = ["sent", "send"]
    private static let said: Set<String> = ["say", "said", "says", "reply", "replied", "replies", "answer", "answered", "hear", "heard", "from"]
    private static let notes: Set<String> = ["note", "notes", "memo", "memos", "recorded", "recording", "recordings"]
    private static let times: Set<String> = ["today", "yesterday", "this", "week"]

    static func when(_ words: [String]) -> LabWhen {
        if words.contains("yesterday") { return .yesterday }
        if words.contains("today") { return .today }
        if words.contains("week") { return .week }
        return .any
    }

    /// The contact or agent a question names: the first whose name shares a word of three letters or more.
    static func person(_ words: [String], people: [String]) -> String {
        for name in people {
            let parts = LabTriggerMatcher.words(name).filter { $0.count >= 3 && $0 != "developer" }
            if parts.contains(where: { words.contains($0) }) { return name }
        }
        return ""
    }

    /// The subject: the words after "about", without the words that say when.
    static func about(_ words: [String]) -> String {
        guard let at = words.lastIndex(of: "about") else { return "" }
        let rest = words[(at + 1)...].filter { !times.contains($0) }.joined(separator: " ")
        return LabNoteSearch.needles(rest).joined(separator: " ")
    }

    static func classify(_ text: String, people: [String]) -> LabQuestion? {
        let words = LabTriggerMatcher.words(text)
        guard !words.isEmpty else { return nil }
        let person = self.person(words, people: people)
        let joined = " " + words.joined(separator: " ") + " "
        let kind: LabAskKind
        if words.contains(where: { decisions.contains($0) }) || joined.contains(" from me ") {
            kind = .decisions
        } else if words.contains(where: { tasks.contains($0) }) || joined.contains(" to do ") {
            kind = .tasks
        } else if words.contains(where: { sent.contains($0) }) || joined.contains(" what happened with ") {
            kind = .sent
        } else if !person.isEmpty, words.contains(where: { said.contains($0) }) {
            kind = .person
        } else if words.contains(where: { notes.contains($0) }) {
            kind = .notes
        } else if !person.isEmpty {
            kind = .person
        } else {
            return nil
        }
        return LabQuestion(kind: kind, about: about(words), person: person, when: when(words))
    }

    /// What the model said, made into a question: the tool is the kind, and its arguments the limits.
    /// A name is kept only if it is someone the app knows.
    static func question(tool: String, arguments: [String: String], people: [String]) -> LabQuestion? {
        guard let kind = LabAskKind(rawValue: tool) else { return nil }
        let about = LabNoteSearch.needles(arguments["about"] ?? "").filter { $0 != "none" && $0 != "any" }.joined(separator: " ")
        let named = LabTriggerMatcher.words(arguments["name"] ?? "")
        let when = LabWhen(rawValue: (arguments["when"] ?? "").lowercased()) ?? .any
        return LabQuestion(kind: kind, about: about, person: person(named, people: people), when: when)
    }
}

/// One node of the app's data, as the query met it.
struct LabWalkStep: Codable, Equatable, Sendable, Identifiable {
    enum Mark: String, Codable, Sendable {
        /// A branch the question leads into.
        case entered
        /// A branch the question does not concern: not opened.
        case skipped
        /// A leaf that fits every limit of the question.
        case matched
        /// A leaf that was looked at and does not fit.
        case passed
    }

    let node: String
    let title: String
    let depth: Int
    let mark: Mark
    let why: String

    var id: String { node }
}

/// A line of an answer, with the node it came from. Nothing in an answer comes from anywhere else.
struct LabAnswerItem: Codable, Equatable, Sendable {
    let node: String
    let line: String
}

/// The query: the code walks the tree of the app's data, branch by branch, and keeps what fits.
enum LabQuery {
    static let branches: [(id: String, title: String)] = [
        ("tasks", "Tasks, from the Actions of every debrief"),
        ("notes", "Notes"),
        ("sent", "What was sent, and to whom"),
        ("replies", "Messages from agents"),
        ("decisions", "What agents are waiting on you for"),
    ]

    private static func enters(_ branch: String, for kind: LabAskKind) -> Bool {
        switch kind {
        case .tasks: return branch == "tasks"
        case .notes: return branch == "notes"
        case .sent: return branch == "sent"
        case .person: return branch == "sent" || branch == "replies"
        case .decisions: return branch == "decisions"
        }
    }

    private static func holds(_ needles: [String], in text: String) -> Bool {
        guard !needles.isEmpty else { return true }
        let hay = LabTriggerMatcher.words(text)
        return needles.allSatisfy { needle in hay.contains { $0.hasPrefix(needle) } }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        !a.isEmpty && LabTriggerMatcher.words(a) == LabTriggerMatcher.words(b)
    }

    /// The replies to a note: messages from an agent that quote its opening words.
    static func replies(to note: LabWorld.NoteItem, in world: LabWorld) -> [LabWorld.MessageItem] {
        world.messages.filter { !$0.fromYou && LabWorld.quote($0.quote, isStartOf: note.transcript) }.sorted { $0.at < $1.at }
    }

    static func run(_ question: LabQuestion, in world: LabWorld) -> (steps: [LabWalkStep], items: [LabAnswerItem]) {
        var steps = [LabWalkStep(node: "root", title: "Everything the app holds", depth: 0, mark: .entered, why: "The walk starts here.")]
        var items: [LabAnswerItem] = []
        let needles = LabNoteSearch.needles(question.about)

        /// Looks at one leaf: the first limit it fails is the reason it is passed over.
        func leaf(_ node: String, _ title: String, line: String, failures: [(Bool, String)]) {
            if let failed = failures.first(where: { !$0.0 }) {
                steps.append(LabWalkStep(node: node, title: title, depth: 2, mark: .passed, why: failed.1))
            } else {
                steps.append(LabWalkStep(node: node, title: title, depth: 2, mark: .matched, why: "Fits the question."))
                items.append(LabAnswerItem(node: node, line: line))
            }
        }

        for branch in branches {
            guard enters(branch.id, for: question.kind) else {
                steps.append(LabWalkStep(node: branch.id, title: branch.title, depth: 1, mark: .skipped, why: "Not what was asked."))
                continue
            }
            steps.append(LabWalkStep(node: branch.id, title: branch.title, depth: 1, mark: .entered, why: "The question is about \(question.kind.title.lowercased())."))
            switch branch.id {
            case "tasks":
                for note in world.notes {
                    for (index, action) in note.actions.enumerated() {
                        leaf("tasks/\(note.id)/\(index)", action, line: "\(action), from the note of \(world.said(note.createdAt))", failures: [
                            (question.when.holds(note.createdAt, in: world), "Its note is not from \(question.when.rawValue)."),
                            (holds(needles, in: action + " " + note.title), "Does not mention \(question.about)."),
                        ])
                    }
                }
            case "notes":
                for note in world.notes {
                    leaf("notes/\(note.id)", note.title, line: "\(note.title), recorded \(world.said(note.createdAt))", failures: [
                        (question.when.holds(note.createdAt, in: world), "Not recorded \(question.when.rawValue)."),
                        (holds(needles, in: note.title + " " + note.transcript), "Does not mention \(question.about)."),
                        (question.person.isEmpty || note.sends.contains { same($0.to, question.person) }, "Was not sent to \(question.person)."),
                    ])
                }
            case "sent":
                for note in world.notes {
                    for (index, send) in note.sends.enumerated() {
                        let answers = replies(to: note, in: world).filter { $0.at >= send.at }
                        let reply = answers.last.map { "\($0.agent) replied \(world.said($0.at)): \($0.text)" } ?? "No reply has come back"
                        leaf("sent/\(note.id)/\(index)", "\(note.title), to \(send.to)",
                             line: "\(note.title), sent to \(send.to) \(world.said(send.at)). \(reply)", failures: [
                            (question.when.holds(send.at, in: world), "Not sent \(question.when.rawValue)."),
                            (holds(needles, in: note.title + " " + note.transcript), "Does not mention \(question.about)."),
                            (question.person.isEmpty || same(send.to, question.person), "Was sent to \(send.to), not to \(question.person)."),
                        ])
                    }
                    if let pending = note.pendingTo, note.sends.isEmpty {
                        let why = note.sendProblem.map { "It has not gone: \($0)" } ?? "It has not gone yet"
                        leaf("sent/\(note.id)/pending", "\(note.title), waiting to go to \(pending)",
                             line: "\(note.title), waiting to go to \(pending). \(why)", failures: [
                            (question.when.holds(note.createdAt, in: world), "Not from \(question.when.rawValue)."),
                            (holds(needles, in: note.title + " " + note.transcript), "Does not mention \(question.about)."),
                            (question.person.isEmpty || same(pending, question.person), "Is for \(pending), not for \(question.person)."),
                        ])
                    }
                }
            case "replies":
                for message in world.messages where !message.fromYou {
                    leaf("replies/\(message.id)", "\(message.agent): \(String(message.text.prefix(60)))",
                         line: "\(message.agent) said \(world.said(message.at)): \(message.text)", failures: [
                        (question.person.isEmpty || same(message.agent, question.person), "Is from \(message.agent), not from \(question.person)."),
                        (question.when.holds(message.at, in: world), "Not from \(question.when.rawValue)."),
                        (holds(needles, in: message.text + " " + (message.quote ?? "")), "Does not mention \(question.about)."),
                    ])
                }
            default:
                for agent in world.agents {
                    let waiting = (agent.waitingFor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    leaf("decisions/\(agent.id)", "\(agent.name): \(waiting.isEmpty ? agent.status : waiting)",
                         line: "\(agent.name) is waiting for: \(waiting)", failures: [
                        (!waiting.isEmpty, "Is not waiting on you for anything."),
                        (question.person.isEmpty || same(agent.name, question.person), "Is \(agent.name), not \(question.person)."),
                        (holds(needles, in: waiting + " " + agent.doing), "Does not mention \(question.about)."),
                    ])
                }
            }
        }
        return (steps, items)
    }
}

/// The answer, put together by the code from the lines the query kept. Nothing is added.
enum LabAnswer {
    static let shownLimit = 10
    static let spokenLimit = 3
    static let unknown = "I could not tell what that asks about. I can answer about your tasks, your notes, what you sent, what someone said, and what is waiting for you."

    private static func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }

    static func head(_ question: LabQuestion, count n: Int) -> String {
        let scope = question.scope
        switch question.kind {
        case .tasks: return n == 0 ? "I found no tasks\(scope)." : "You have \(count(n, "task", "tasks"))\(scope)."
        case .notes: return n == 0 ? "I found no notes\(scope)." : "I found \(count(n, "note", "notes"))\(scope)."
        case .sent: return n == 0 ? "I found nothing sent\(scope)." : "I found \(count(n, "note", "notes")) sent\(scope)."
        case .person:
            let who = question.person.isEmpty ? "that person" : question.person
            return n == 0 ? "I found nothing sent to or said by \(who)\(scope)." : "I found \(count(n, "thing", "things")) about \(who)\(scope)."
        case .decisions: return n == 0 ? "Nothing is waiting for you\(scope)." : "\(count(n, "thing is", "things are")) waiting for you\(scope)."
        }
    }

    private static func body(_ items: [LabAnswerItem], limit: Int) -> String {
        var lines = items.prefix(limit).enumerated().map { item in
            "\(item.offset + 1). " + item.element.line.trimmingCharacters(in: CharacterSet(charactersIn: " .")) + "."
        }
        if items.count > limit { lines.append("And \(items.count - limit) more.") }
        return lines.joined(separator: "\n")
    }

    /// The answer as shown, and a shorter one to be spoken.
    static func build(_ question: LabQuestion?, items: [LabAnswerItem]) -> (shown: String, spoken: String) {
        guard let question else { return (unknown, unknown) }
        let head = head(question, count: items.count)
        if items.isEmpty { return (head, head) }
        return (head + "\n" + body(items, limit: shownLimit), head + "\n" + body(items, limit: spokenLimit))
    }
}

/// One question taken all the way: what was asked, what each engine made of it, the walk through
/// the data, the answer, and how long each part took.
struct LabAskTurn: Codable, Equatable, Sendable, Identifiable {
    let number: Int
    let at: Date
    let question: String
    /// spoken, typed or preset.
    let source: String
    /// What the word lists made of it, and what the model made of it.
    var rules: LabQuestion?
    var model: LabQuestion?
    var modelAsked = false
    /// model, rules or neither: whose reading the query used. The model's is used when it called a tool.
    var used = "neither"
    var record: ModelDoorRecord?
    /// Instructions, question and tool descriptions together, at four characters a token.
    var aboutTokensIn: Int?
    var queryMs = 0.0
    var steps: [LabWalkStep] = []
    var items: [LabAnswerItem] = []
    var shown = ""
    var spoken = ""
    /// How long the answer took to say aloud, when it was said.
    var spokeMs: Double?

    var id: Int { number }
    var asked: LabQuestion? { used == "model" ? model : (used == "rules" ? rules : nil) }
    var modelMs: Double? { record?.totalMs }

    /// The small notice for a turn: who read the question, and the time of each part.
    var notice: String {
        var parts: [String] = []
        if modelAsked {
            if let error = record?.error {
                parts.append("model could not answer (\(error.kind))")
            } else if let ms = modelMs {
                parts.append("model \(Timecode.duration(seconds: ms / 1000))" + (aboutTokensIn.map { ", about \($0) tokens in" } ?? ""))
            }
        }
        parts.append("query \((queryMs * 10).rounded() / 10) ms over \(steps.count) nodes")
        if let spokeMs { parts.append("spoken in \(Timecode.duration(seconds: spokeMs / 1000))") }
        return "Turn \(number): read by \(used == "neither" ? "neither engine" : "the \(used)"), " + parts.joined(separator: ", ")
    }

    /// Takes in the model's record: the first tool it called, if it is one of the kinds, is its reading.
    mutating func take(_ record: ModelDoorRecord, people: [String]) {
        self.record = record
        let sent = record.instructions + record.prompt + record.toolsOffered.map { $0.name + $0.description }.joined()
        aboutTokensIn = LabLabelWindow.aboutTokens(sent)
        if record.error == nil, let call = record.toolCalls.first(where: { LabAskKind(rawValue: $0.name) != nil }) {
            model = LabAskRules.question(tool: call.name, arguments: call.arguments, people: people)
        }
    }

    /// Settles a turn once both engines have spoken: picks the reading, walks the data, builds the answer.
    mutating func settle(in world: LabWorld) {
        used = model != nil ? "model" : (rules != nil ? "rules" : "neither")
        let clock = ContinuousClock()
        let start = clock.now
        if let asked {
            let result = LabQuery.run(asked, in: world)
            steps = result.steps
            items = result.items
        }
        let answer = LabAnswer.build(asked, items: items)
        shown = answer.shown
        spoken = answer.spoken
        let elapsed = clock.now - start
        queryMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
}

enum LabAskPrompt {
    /// Plain, with nothing the model could copy.
    static let instructions = "You are given one question that a person asked about their own voice notes app. Work out what kind of thing the question asks for, and call the one tool for that kind, once. Fill in only what the question says. If the question is not about tasks, notes, something that was sent, a person or decisions, call no tool and answer with the one word none."

    /// Questions kept ready, so the same set can be asked on every device.
    static let presets = [
        "What are my tasks?",
        "What happened with the memo I sent yesterday?",
        "Which notes did I record today?",
        "What is waiting for me?",
        "What did Claude say?",
        "Which notes are about the vault?",
        "What is the weather like?",
    ]
}

/// A whole session of questions, for export.
struct LabAskLog: Codable, Equatable, Sendable {
    var experiment: String
    var device: LabDevice
    var instructions: String
    var turns: [LabAskTurn]

    var json: String { LabRun.json(of: self) }
}
