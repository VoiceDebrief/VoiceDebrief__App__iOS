import Foundation
import Testing
@testable import VoiceDebrief

/// A small world with fixed times: Sunday 15 November 2026, 12:00 UTC.
enum LabAskFixture {
    static let now = Date(timeIntervalSince1970: 1_794_744_000)
    static let todayMorning = Date(timeIntervalSince1970: 1_794_733_200)
    static let yesterdayMorning = Date(timeIntervalSince1970: 1_794_650_400)
    static let threeDaysAgo = Date(timeIntervalSince1970: 1_794_484_800)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static var world: LabWorld {
        LabWorld(
            now: now,
            calendar: calendar,
            notes: [
                LabWorld.NoteItem(id: "n1", createdAt: todayMorning, title: "Plan the vault remotes",
                                  transcript: "We need a second remote for the vault. Ask Maria about the entitlement.",
                                  actions: ["Ask Maria about the entitlement", "Add a second remote"], sends: []),
                LabWorld.NoteItem(id: "n2", createdAt: yesterdayMorning, title: "Memo about the boiler",
                                  transcript: "This is a memo about the boiler quote. The plumber comes on Tuesday.",
                                  actions: ["Call the plumber"],
                                  sends: [LabWorld.Send(to: "Claude (developer)", at: yesterdayMorning.addingTimeInterval(300))]),
                LabWorld.NoteItem(id: "n3", createdAt: threeDaysAgo, title: "Shopping", transcript: "Buy milk.", actions: [], sends: [],
                                  pendingTo: "Maria Silva", sendProblem: "The server could not be reached."),
            ],
            contacts: ["Claude (developer)", "Maria Silva"],
            agents: [
                LabWorld.AgentItem(id: "a1", name: "Website Conductor", status: "waiting", doing: "The identity page",
                                   waitingFor: "A decision on the passkey domain"),
                LabWorld.AgentItem(id: "a2", name: "Lab", status: "working", doing: "L06", waitingFor: nil),
            ],
            messages: [
                LabWorld.MessageItem(id: "m1", agent: "Website Conductor", fromYou: false, at: yesterdayMorning.addingTimeInterval(3600),
                                     text: "The quote looks high. Ask for a second one.", quote: "This is a memo about the boiler quote"),
                LabWorld.MessageItem(id: "m2", agent: "Website Conductor", fromYou: true, at: yesterdayMorning.addingTimeInterval(7200),
                                     text: "Thanks.", quote: nil),
            ])
    }
}

@Suite("Lab L06: the app's data, copied out")
struct LabWorldTests {
    @Test func theActionsOfADebriefAreItsTasks() {
        let debrief = "## Key points\n- The boiler is old.\n\n## Actions\n- [me] Call the plumber\n- **[Maria]** Send the quote\n- plain one\n\n## In one sentence\nThe boiler.\n"
        #expect(LabWorld.actions(in: debrief) == ["Call the plumber", "Maria: Send the quote", "plain one"])
        #expect(LabWorld.actions(in: "## Actions\n- none mentioned\n").isEmpty)
        #expect(LabWorld.actions(in: nil).isEmpty)
    }

    @Test func aReplyBelongsToTheNoteItQuotes() {
        #expect(LabWorld.quote("This is a memo about the boiler quote", isStartOf: "This is a memo about the boiler quote. The plumber comes."))
        #expect(LabWorld.quote("this is a memo, about the BOILER…", isStartOf: "This is a memo about the boiler quote."))
        #expect(!LabWorld.quote("We need a second remote", isStartOf: "This is a memo about the boiler quote."))
        #expect(!LabWorld.quote("This is", isStartOf: "This is a memo about the boiler quote."))
        #expect(!LabWorld.quote(nil, isStartOf: "This is a memo."))
    }

    @Test func timesAreSaidTheWayAPersonWould() {
        let world = LabAskFixture.world
        #expect(world.said(LabAskFixture.todayMorning) == "today at 09:00")
        #expect(world.said(LabAskFixture.yesterdayMorning) == "yesterday at 10:00")
        #expect(world.said(LabAskFixture.threeDaysAgo) == "12 November at 12:00")
        #expect(world.people == ["Claude (developer)", "Maria Silva", "Website Conductor", "Lab"])
        #expect(LabWhen.week.holds(LabAskFixture.threeDaysAgo, in: world))
        #expect(!LabWhen.yesterday.holds(LabAskFixture.todayMorning, in: world))
    }
}

@Suite("Lab L06: what kind of thing is asked")
struct LabAskRulesTests {
    static let people = LabAskFixture.world.people

    static func read(_ text: String) -> LabQuestion? { LabAskRules.classify(text, people: people) }

    @Test func theWordListsReadTheQuestionsKeptReady() {
        #expect(Self.read("What are my tasks?") == LabQuestion(kind: .tasks))
        #expect(Self.read("What happened with the memo I sent yesterday?") == LabQuestion(kind: .sent, when: .yesterday))
        #expect(Self.read("Which notes did I record today?") == LabQuestion(kind: .notes, when: .today))
        #expect(Self.read("What is waiting for me?") == LabQuestion(kind: .decisions))
        #expect(Self.read("What did Claude say?") == LabQuestion(kind: .person, person: "Claude (developer)"))
        #expect(Self.read("Which notes are about the vault?") == LabQuestion(kind: .notes, about: "vault"))
        #expect(Self.read("What is the weather like?") == nil)
        #expect(Self.read("") == nil)
        #expect(LabAskPrompt.presets.filter { Self.read($0) != nil }.count == LabAskPrompt.presets.count - 1)
    }

    @Test func aSubjectAPersonAndATimeAreReadTogether() {
        #expect(Self.read("What do I have to do about the boiler this week?") == LabQuestion(kind: .tasks, about: "boiler", when: .week))
        #expect(Self.read("What did I send to Maria about the entitlement?") == LabQuestion(kind: .sent, about: "entitlement", person: "Maria Silva"))
        #expect(Self.read("Anything from the website conductor?") == LabQuestion(kind: .person, person: "Website Conductor"))
    }

    @Test func theModelsToolCallBecomesAQuestionAndOnlyAKnownNameIsKept() {
        #expect(LabAskRules.question(tool: "findNotes", arguments: ["about": "none", "when": "Yesterday"], people: Self.people)
                == LabQuestion(kind: .notes, when: .yesterday))
        #expect(LabAskRules.question(tool: "findTasks", arguments: ["about": "the boiler quote"], people: Self.people)
                == LabQuestion(kind: .tasks, about: "boiler quote"))
        #expect(LabAskRules.question(tool: "findPerson", arguments: ["name": "claude"], people: Self.people)
                == LabQuestion(kind: .person, person: "Claude (developer)"))
        #expect(LabAskRules.question(tool: "findPerson", arguments: ["name": "Bob"], people: Self.people) == LabQuestion(kind: .person))
        #expect(LabAskRules.question(tool: "findDecisions", arguments: [:], people: Self.people) == LabQuestion(kind: .decisions))
        #expect(LabAskRules.question(tool: "deleteEverything", arguments: [:], people: Self.people) == nil)
        for text in LabAskKind.allCases.map(\.summary) + [LabAskPrompt.instructions] {
            #expect(!text.contains("\""))
        }
        #expect(LabAskToolkit().definitions.map(\.name) == ["findTasks", "findNotes", "findSent", "findPerson", "findDecisions"])
    }
}

@Suite("Lab L06: the walk and the answer")
struct LabQueryTests {
    static let world = LabAskFixture.world

    static func marks(_ steps: [LabWalkStep]) -> [String] { steps.map { "\($0.node)=\($0.mark.rawValue)" } }

    @Test func tasksAreFoundInTheirBranchAndTheOthersStayClosed() {
        let result = LabQuery.run(LabQuestion(kind: .tasks), in: Self.world)
        #expect(Self.marks(result.steps) == [
            "root=entered", "tasks=entered", "tasks/n1/0=matched", "tasks/n1/1=matched", "tasks/n2/0=matched",
            "notes=skipped", "sent=skipped", "replies=skipped", "decisions=skipped",
        ])
        #expect(result.items.map(\.node) == ["tasks/n1/0", "tasks/n1/1", "tasks/n2/0"])
        #expect(LabAnswer.build(LabQuestion(kind: .tasks), items: result.items).shown == """
            You have 3 tasks.
            1. Ask Maria about the entitlement, from the note of today at 09:00.
            2. Add a second remote, from the note of today at 09:00.
            3. Call the plumber, from the note of yesterday at 10:00.
            """)
    }

    @Test func eachLimitNarrowsTheWalkAndSaysWhyALeafWasPassed() {
        let about = LabQuery.run(LabQuestion(kind: .tasks, about: "plumber"), in: Self.world)
        #expect(about.items.map(\.node) == ["tasks/n2/0"])
        #expect(about.steps.first { $0.node == "tasks/n1/0" }?.why == "Does not mention plumber.")
        let today = LabQuery.run(LabQuestion(kind: .tasks, when: .today), in: Self.world)
        #expect(today.items.map(\.node) == ["tasks/n1/0", "tasks/n1/1"])
        #expect(today.steps.first { $0.node == "tasks/n2/0" }?.why == "Its note is not from today.")
        let notes = LabQuery.run(LabQuestion(kind: .notes, about: "vault"), in: Self.world)
        #expect(notes.items.map(\.line) == ["Plan the vault remotes, recorded today at 09:00"])
        #expect(LabQuery.run(LabQuestion(kind: .notes, about: "garden"), in: Self.world).items.isEmpty)
    }

    @Test func whatWasSentComesWithItsReplyOrSaysThereIsNone() {
        let yesterday = LabQuery.run(LabQuestion(kind: .sent, when: .yesterday), in: Self.world)
        #expect(yesterday.items.map(\.line) == [
            "Memo about the boiler, sent to Claude (developer) yesterday at 10:05. Website Conductor replied yesterday at 11:00: The quote looks high. Ask for a second one.",
        ])
        #expect(yesterday.steps.first { $0.node == "sent/n3/pending" }?.mark == .passed)
        let all = LabQuery.run(LabQuestion(kind: .sent), in: Self.world)
        #expect(all.items.map(\.node) == ["sent/n2/0", "sent/n3/pending"])
        #expect(all.items.last?.line == "Shopping, waiting to go to Maria Silva. It has not gone: The server could not be reached.")
        let answer = LabAnswer.build(LabQuestion(kind: .sent, when: .yesterday), items: yesterday.items)
        #expect(answer.shown == "I found 1 note sent from yesterday.\n1. Memo about the boiler, sent to Claude (developer) yesterday at 10:05. Website Conductor replied yesterday at 11:00: The quote looks high. Ask for a second one.")
        #expect(answer.spoken == answer.shown)
    }

    @Test func decisionsAreWhatAgentsAreWaitingOnYouFor() {
        let result = LabQuery.run(LabQuestion(kind: .decisions), in: Self.world)
        #expect(result.items.map(\.line) == ["Website Conductor is waiting for: A decision on the passkey domain"])
        #expect(result.steps.first { $0.node == "decisions/a2" }?.why == "Is not waiting on you for anything.")
        #expect(LabAnswer.build(LabQuestion(kind: .decisions), items: result.items).shown
                == "1 thing is waiting for you.\n1. Website Conductor is waiting for: A decision on the passkey domain.")
        #expect(LabAnswer.build(LabQuestion(kind: .decisions), items: []).shown == "Nothing is waiting for you.")
    }

    @Test func aPersonIsLookedForInWhatWasSentAndWhatWasSaid() {
        let result = LabQuery.run(LabQuestion(kind: .person, person: "Website Conductor"), in: Self.world)
        #expect(result.steps.filter { $0.mark == .entered }.map(\.node) == ["root", "sent", "replies"])
        #expect(result.items.map(\.node) == ["replies/m1"])
        #expect(result.steps.first { $0.node == "sent/n2/0" }?.why == "Was sent to Claude (developer), not to Website Conductor.")
        #expect(LabAnswer.build(LabQuestion(kind: .person, person: "Website Conductor"), items: result.items).shown
                == "I found 1 thing about Website Conductor.\n1. Website Conductor said yesterday at 11:00: The quote looks high. Ask for a second one.")
    }

    @Test func aLongAnswerIsShortenedWhenSpokenAndNothingFoundSaysSo() {
        let items = (1...5).map { LabAnswerItem(node: "tasks/x/\($0)", line: "Task \($0)") }
        let answer = LabAnswer.build(LabQuestion(kind: .tasks, about: "garden"), items: items)
        #expect(answer.shown.components(separatedBy: "\n").count == 6)
        #expect(answer.spoken == "You have 5 tasks about garden.\n1. Task 1.\n2. Task 2.\n3. Task 3.\nAnd 2 more.")
        #expect(LabAnswer.build(LabQuestion(kind: .tasks, about: "garden"), items: []).shown == "I found no tasks about garden.")
        #expect(LabAnswer.build(nil, items: []).spoken == LabAnswer.unknown)
    }
}

@Suite("Lab L06: a turn")
struct LabAskTurnTests {
    /// A door record in which this tool was called, made with the door's own recorder.
    static func record(calling name: String?, arguments: [String: String] = [:], error: ModelDoorError? = nil) -> ModelDoorRecord {
        let recorder = ModelDoorRecorder()
        if let name { _ = recorder.measure(tool: name, arguments: arguments) { LabAskToolkit.reply } }
        var record = ModelDoorRecord(startedAt: LabAskFixture.now, instructions: LabAskPrompt.instructions, prompt: "What are my tasks?",
                                     policy: ModelDoorPolicy(allowedTools: LabAskKind.allCases.map(\.rawValue)),
                                     toolsOffered: LabAskToolkit().definitions, toolsWithheld: [])
        record.toolCalls = recorder.toolCalls
        record.error = error
        record.totalMs = 900
        return record
    }

    static func turn(_ question: String) -> LabAskTurn {
        var turn = LabAskTurn(number: 1, at: LabAskFixture.now, question: question, source: "typed")
        turn.rules = LabAskRules.classify(question, people: LabAskFixture.world.people)
        return turn
    }

    @Test func withNoModelTheWordListsReadingIsUsed() {
        var turn = Self.turn("What are my tasks?")
        turn.settle(in: LabAskFixture.world)
        #expect(turn.used == "rules")
        #expect(turn.items.count == 3)
        #expect(turn.shown.hasPrefix("You have 3 tasks."))
        #expect(turn.notice.hasPrefix("Turn 1: read by the rules, query "))
        #expect(turn.notice.hasSuffix(" ms over 9 nodes"))
    }

    @Test func theModelsReadingIsUsedWhenItCalledATool() {
        var turn = Self.turn("What are my tasks?")
        turn.modelAsked = true
        turn.take(Self.record(calling: "findDecisions"), people: LabAskFixture.world.people)
        turn.settle(in: LabAskFixture.world)
        #expect(turn.used == "model")
        #expect(turn.rules?.kind == .tasks)
        #expect(turn.model?.kind == .decisions)
        #expect(turn.shown.hasPrefix("1 thing is waiting for you."))
        #expect((turn.aboutTokensIn ?? 0) > 100)
        #expect(turn.notice.contains("model 0.9 s, about \(turn.aboutTokensIn ?? 0) tokens in"))
    }

    @Test func aModelThatCallsNothingOrFailsLeavesTheWordLists() {
        var silent = Self.turn("What are my tasks?")
        silent.modelAsked = true
        silent.take(Self.record(calling: nil), people: [])
        silent.settle(in: LabAskFixture.world)
        #expect(silent.used == "rules")
        var failed = Self.turn("What are my tasks?")
        failed.modelAsked = true
        failed.take(Self.record(calling: "findDecisions", error: ModelDoorError(kind: "unavailable", words: "w", raw: "")), people: [])
        failed.settle(in: LabAskFixture.world)
        #expect(failed.model == nil)
        #expect(failed.used == "rules")
        #expect(failed.notice.contains("model could not answer (unavailable)"))
    }

    @Test func aQuestionNeitherEngineCanReadIsAnsweredHonestly() {
        var turn = Self.turn("What is the weather like?")
        turn.settle(in: LabAskFixture.world)
        #expect(turn.used == "neither")
        #expect(turn.steps.isEmpty)
        #expect(turn.shown == LabAnswer.unknown)
        #expect(turn.notice.hasPrefix("Turn 1: read by neither engine, "))
    }
}

@Suite("Lab L05 and L06: the desk and the conversation")
@MainActor
struct LabAskDeskTests {
    static func desk() -> LabAskDesk {
        let desk = LabAskDesk(experiment: "L06")
        desk.askModel = false
        desk.world = { LabAskFixture.world }
        return desk
    }

    @Test func aQuestionIsAnsweredFromTheWorldAndTheLogSurvivesItsJSON() async throws {
        let desk = Self.desk()
        let first = await desk.ask("  What is waiting for me?  ", source: "typed", now: LabAskFixture.now)
        let turn = try #require(first)
        #expect(turn.number == 1)
        #expect(turn.question == "What is waiting for me?")
        #expect(!turn.modelAsked)
        #expect(turn.shown == "1 thing is waiting for you.\n1. Website Conductor is waiting for: A decision on the passkey domain.")
        let empty = await desk.ask("   ", source: "typed")
        #expect(empty == nil)
        await desk.ask("What are my tasks?", source: "preset", now: LabAskFixture.now)
        #expect(desk.turns.map(\.number) == [2, 1])
        desk.spoke(2, ms: 3200)
        #expect(desk.turns[0].spokeMs == 3200)
        #expect(desk.turns[0].notice.hasSuffix("spoken in 3.2 s"))

        let json = desk.log.json
        #expect(json.contains("\"experiment\" : \"L06\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LabAskLog.self, from: Data(json.utf8))
        #expect(back.turns.map(\.shown) == desk.turns.map(\.shown))
        #expect(back.turns.map(\.steps) == desk.turns.map(\.steps))
        desk.clear()
        #expect(desk.turns.isEmpty)
    }

    @Test func aTypedQuestionInTheConversationIsAnsweredAndLeavesItIdle() async {
        let desk = Self.desk()
        let talk = LabTalkBack(desk: desk, host: LabActionHost())
        talk.speakAnswers = false
        await talk.type("What happened with the memo I sent yesterday?")
        #expect(talk.state == .idle)
        #expect(desk.turns.count == 1)
        #expect(desk.turns[0].spoken.hasPrefix("I found 1 note sent from yesterday."))
        #expect(desk.turns[0].spokeMs == nil)
    }

    @Test func theConversationDoesNotStartWhileANoteIsBeingRecorded() async {
        let host = LabActionHost()
        host.isRecording = { true }
        let talk = LabTalkBack(desk: Self.desk(), host: host)
        await talk.start(localeId: "en-GB")
        #expect(!talk.running)
        #expect(talk.state == .idle)
        #expect(talk.problem == "A note is being recorded. The Lab does not listen at the same time.")
        await talk.stop()
        #expect(talk.state == .idle)
    }
}

@Suite("Lab L05: speaking takes the app's one turn")
@MainActor
struct LabSpeakerTests {
    @Test func nothingIsSaidWhileSomethingElseHoldsTheTurnOrANoteIsBeingRecorded() async {
        let turn = MicrophoneTurn()
        let other = UUID()
        #expect(turn.take(other))
        let mine = UUID()
        #expect(!turn.take(mine))
        turn.giveBack(mine)
        #expect(turn.holder == other)
        turn.giveBack(other)
        #expect(turn.take(mine))
        #expect(turn.take(mine))

        let host = LabActionHost()
        host.isRecording = { true }
        let speaker = LabSpeaker(host: host)
        let said = await speaker.speak("You have 3 tasks.", localeId: "en-GB")
        #expect(said == nil)
        #expect(speaker.problem == "Not said aloud: a note is being recorded.")
        let nothing = await speaker.speak("   ", localeId: "en-GB")
        #expect(nothing == nil)
        #expect(speaker.problem == nil)
    }
}
