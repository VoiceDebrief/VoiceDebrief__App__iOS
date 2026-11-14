import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Lab L04: labels and who a note is for")
struct LabLabelFieldTests {
    static let people = [
        LabLabelCandidate(id: "c1", name: "Claude (developer)", kind: "conductor"),
        LabLabelCandidate(id: "c2", name: "Maria Silva", kind: "person"),
        LabLabelCandidate(id: "c3", name: "Website Conductor", kind: "conductor"),
        LabLabelCandidate(id: "c4", name: "Maria Costa", kind: "person"),
    ]

    @Test func everyLabelHasItsOwnToolAndNothingForAModelToCopy() {
        #expect(LabLabelField.find("forWhom")?.tool == "setForWhom")
        #expect(LabLabelField.find(tool: "setNextAction")?.id == "nextAction")
        #expect(Set(LabLabelField.all.map(\.tool)).count == LabLabelField.all.count)
        #expect(LabLabelField.inUse([]).map(\.id) == ["forWhom", "topic", "title", "urgency"])
        #expect(LabLabelField.inUse(["project", "kind"]).map(\.id) == ["forWhom", "topic", "title", "urgency", "kind", "project"])
        for text in LabLabelField.all.map(\.summary) + [LabLabelPrompt.instructions] {
            #expect(!text.contains("\""))
        }
        let toolkit = LabLabelToolkit(fields: LabLabelField.inUse([]))
        #expect(toolkit.definitions.map(\.name) == ["setForWhom", "setTopic", "setTitle", "setUrgency"])
    }

    @Test func aNameIsMatchedOnlyWhenItMeansOnePerson() {
        #expect(LabLabelMatch.person("the website conductor", among: Self.people)?.id == "c3")
        #expect(LabLabelMatch.person("Claude", among: Self.people)?.id == "c1")
        #expect(LabLabelMatch.person("maria silva", among: Self.people)?.id == "c2")
        // Two Marias: the code does not guess.
        #expect(LabLabelMatch.person("Maria", among: Self.people) == nil)
        #expect(LabLabelMatch.person("the plumber", among: Self.people) == nil)
        #expect(LabLabelMatch.person("the", among: Self.people) == nil)
    }
}

@Suite("Lab L04: the board owns the labels")
struct LabLabelBoardTests {
    static let inUse = LabLabelField.inUse(["kind"])
    static let people = LabLabelFieldTests.people

    @Test func theModelsValueIsTakenTidiedAndNotTakenTwice() {
        var board = LabLabelBoard()
        #expect(board.propose("  The boiler quote. ", for: "topic", loop: 1, inUse: Self.inUse, candidates: Self.people) == .changed)
        #expect(board.values["topic"] == LabLabelValue(text: "The boiler quote", source: "model", loop: 1, matched: nil))
        #expect(board.propose("the boiler quote", for: "topic", loop: 2, inUse: Self.inUse, candidates: Self.people) == .same)
        #expect(board.values["topic"]?.loop == 1)
        #expect(board.propose("Plumbing", for: "topic", loop: 3, inUse: Self.inUse, candidates: Self.people) == .changed)
        #expect(board.values["topic"]?.text == "Plumbing")
    }

    @Test func aValueALabelCannotHoldIsRefused() {
        var board = LabLabelBoard()
        #expect(board.propose("HIGH", for: "urgency", loop: 1, inUse: Self.inUse, candidates: []) == .changed)
        #expect(board.values["urgency"]?.text == "high")
        #expect(board.propose("extremely", for: "urgency", loop: 2, inUse: Self.inUse, candidates: []) == .rejected)
        #expect(board.propose("   ", for: "topic", loop: 2, inUse: Self.inUse, candidates: []) == .rejected)
        // A label that is not in use, and a label that does not exist.
        #expect(board.propose("Lab", for: "project", loop: 2, inUse: Self.inUse, candidates: []) == .rejected)
        #expect(board.propose("x", for: "colour", loop: 2, inUse: Self.inUse, candidates: []) == .rejected)
        #expect(board.values.keys.sorted() == ["urgency"])
        let long = String(repeating: "word ", count: 40)
        #expect(board.propose(long, for: "topic", loop: 3, inUse: Self.inUse, candidates: []) == .changed)
        #expect(board.values["topic"]?.text.count == LabLabelBoard.longest)
    }

    @Test func whatThePersonSaysStandsAndTheModelCannotMoveIt() {
        var board = LabLabelBoard()
        _ = board.propose("Holidays", for: "topic", loop: 1, inUse: Self.inUse, candidates: [])
        let pinned = board.override("X, Y, Z", for: "topic", candidates: [])
        #expect(pinned)
        #expect(board.isPinned("topic"))
        #expect(board.values["topic"] == LabLabelValue(text: "X, Y, Z", source: "voice", loop: nil, matched: nil))
        #expect(board.propose("Holidays", for: "topic", loop: 2, inUse: Self.inUse, candidates: []) == .pinned)
        #expect(board.values["topic"]?.text == "X, Y, Z")
        // Handed back to the model: the value stays until the model offers another.
        board.unpin("topic")
        #expect(board.values["topic"]?.text == "X, Y, Z")
        #expect(board.propose("Holidays", for: "topic", loop: 3, inUse: Self.inUse, candidates: []) == .changed)
        // A choice the label does not have is not an override.
        let refused = board.override("sky high", for: "urgency", candidates: [])
        #expect(!refused)
        #expect(!board.isPinned("urgency"))
    }

    @Test func whoItIsForIsMatchedToAContactAndTravelsWithTheNote() {
        var board = LabLabelBoard()
        #expect(board.recipient == nil)
        _ = board.propose("the website conductor", for: "forWhom", loop: 1, inUse: Self.inUse, candidates: Self.people)
        #expect(board.values["forWhom"]?.text == "Website Conductor")
        #expect(board.recipient?.id == "c3")
        // A name nobody has is kept as it was said, and matched to no one.
        board.override("Maria", for: "forWhom", candidates: Self.people)
        #expect(board.values["forWhom"]?.text == "Maria")
        #expect(board.recipient == nil)
        _ = board.propose("Budget for March", for: "title", loop: 1, inUse: Self.inUse, candidates: [])
        #expect(board.title == "Budget for March")
        let data = try? JSONEncoder().encode(board)
        #expect(data.flatMap { try? JSONDecoder().decode(LabLabelBoard.self, from: $0) } == board)
    }
}

@Suite("Lab L04: setting a label by saying so")
struct LabLabelOverrideTests {
    static let inUse = LabLabelField.inUse(["kind"])

    static func detect(_ sentence: String) -> [String] {
        LabLabelOverrides.detect(sentence, inUse: inUse).map { "\($0.field)=\($0.value)" }
    }

    @Test func theOwnersOwnWordsSetTheLabels() {
        #expect(Self.detect("This is a memo for the website conductor.") == ["forWhom=the website conductor"])
        #expect(Self.detect("No, the topic is X, Y, Z.") == ["topic=X, Y, Z"])
        #expect(Self.detect("The title is Budget for March") == ["title=Budget for March"])
        #expect(Self.detect("OK so this one is for Maria Silva") == ["forWhom=Maria Silva"])
        #expect(Self.detect("urgency is high") == ["urgency=high"])
        #expect(Self.detect("And the kind is idea.") == ["kind=idea"])
    }

    @Test func urgentAndNotUrgent() {
        #expect(Self.detect("By the way this is urgent.") == ["urgency=high"])
        #expect(Self.detect("This is not urgent.") == ["urgency=low"])
        #expect(Self.detect("It isn't urgent") == ["urgency=low"])
    }

    @Test func ordinarySpeechSetsNothing() {
        #expect(Self.detect("I spoke to the plumber about the boiler and he will come on Tuesday.").isEmpty)
        #expect(Self.detect("The topic is").isEmpty)
        #expect(Self.detect("urgency is sky high").isEmpty)
        #expect(Self.detect("").isEmpty)
        // A label that is not in use is not listened for.
        #expect(Self.detect("The project is the Lab").isEmpty)
        #expect(LabLabelOverrides.detect("The project is the Lab", inUse: LabLabelField.inUse(["project"])).map(\.value) == ["the Lab"])
    }
}

@Suite("Lab L04: the window of words and the loop")
struct LabLabelLoopTests {
    static let at = Date(timeIntervalSince1970: 1_794_680_000)
    static let inUse = LabLabelField.inUse([])

    /// A door record in which these label tools were called, made with the door's own recorder.
    static func record(_ calls: [(String, String)], error: ModelDoorError? = nil) -> ModelDoorRecord {
        let recorder = ModelDoorRecorder()
        for call in calls { _ = recorder.measure(tool: call.0, arguments: ["value": call.1]) { LabLabelToolkit.reply } }
        let toolkit = LabLabelToolkit(fields: inUse)
        var record = ModelDoorRecord(startedAt: at, instructions: LabLabelPrompt.instructions, prompt: "Words of the note so far:\nHello",
                                     policy: ModelDoorPolicy(allowedTools: inUse.map(\.tool)), toolsOffered: toolkit.definitions, toolsWithheld: [])
        record.toolCalls = recorder.toolCalls
        record.error = error
        record.totalMs = 1900
        return record
    }

    @Test func theWindowIsTheEndOfTheWordsFromAWholeWord() {
        let words = (1...400).map { "word\($0)" }.joined(separator: " ")
        #expect(LabLabelWindow.take(words, tokens: 0) == words)
        #expect(LabLabelWindow.take("  short note  ", tokens: 250) == "short note")
        let window = LabLabelWindow.take(words, tokens: 250)
        #expect(window.count <= 1000)
        #expect(window.hasSuffix("word400"))
        #expect(window.hasPrefix("word"))
        #expect(words.hasSuffix(window))
        #expect(LabLabelWindow.aboutTokens("12345678") == 2)
        #expect(LabLabelWindow.aboutTokens("123456789") == 3)
    }

    @Test func thePromptHandsOverTheStateAndTheWords() {
        var board = LabLabelBoard()
        board.override("X, Y, Z", for: "topic", candidates: [])
        let prompt = LabLabelPrompt.prompt(board: board, inUse: Self.inUse, candidates: LabLabelFieldTests.people, window: "We need a second remote.")
        #expect(prompt == """
            Labels so far. Topic: X, Y, Z.
            People and agents the note can be for: Claude (developer), Maria Silva, Website Conductor, Maria Costa.
            Words of the note so far:
            We need a second remote.
            """)
        #expect(LabLabelPrompt.prompt(board: LabLabelBoard(), inUse: Self.inUse, candidates: [], window: "Hello") == "Words of the note so far:\nHello")
    }

    @Test func aLoopSaysWhatWasOfferedWhatChangedAndHowLongItTook() {
        var board = LabLabelBoard()
        board.override("X, Y, Z", for: "topic", candidates: [])
        let record = Self.record([("setTitle", "Second remote"), ("setTopic", "Vaults"), ("setUrgency", "soon"), ("setColour", "red")])
        let loop = LabLabelLoop.apply(record, to: &board, number: 3, windowTokens: 1000, window: "Hello", transcript: "Well. Hello",
                                      inUse: Self.inUse, candidates: [])
        #expect(loop.proposals.map(\.field) == ["title", "topic", "urgency"])
        #expect(loop.proposals.map(\.outcome) == [.changed, .pinned, .rejected])
        #expect(loop.changed == ["title"])
        #expect(board.values["title"]?.loop == 3)
        #expect(board.values["topic"]?.text == "X, Y, Z")
        #expect(loop.windowCharacters == 5)
        #expect(loop.transcriptCharacters == 11)
        #expect(loop.totalMs == 1900)
        #expect(loop.firstCallMs != nil)
        #expect(loop.aboutTokensIn > 50)
        #expect(loop.notice.hasPrefix("Loop 3: "))
        #expect(loop.notice.hasSuffix("1.9 s in all, about \(loop.aboutTokensIn) tokens in, changed: Title"))
    }

    @Test func aLoopWithNothingOfferedOrAnErrorSaysSo() {
        var board = LabLabelBoard()
        let quiet = LabLabelLoop.apply(Self.record([]), to: &board, number: 1, windowTokens: 0, window: "Hello", transcript: "Hello",
                                       inUse: Self.inUse, candidates: [])
        #expect(quiet.firstCallMs == nil)
        #expect(quiet.notice == "Loop 1: no label offered, 1.9 s in all, about \(quiet.aboutTokensIn) tokens in, nothing changed")
        let failed = LabLabelLoop.apply(Self.record([], error: ModelDoorError(kind: "contextExceeded", words: "Too long for the model.", raw: "")),
                                        to: &board, number: 2, windowTokens: 0, window: "Hello", transcript: "Hello", inUse: Self.inUse, candidates: [])
        #expect(failed.notice == "Loop 2: Too long for the model. (1.9 s)")
        #expect(board == LabLabelBoard())
    }
}

@Suite("Lab L04: the desk")
@MainActor
struct LabLabelsDeskTests {
    static func desk(host: LabActionHost = LabActionHost()) -> (LabLabelsDesk, UserDefaults) {
        let defaults = UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!
        return (LabLabelsDesk(defaults: defaults, host: host), defaults)
    }

    @Test func whatIsSaidAboutALabelIsPinnedAtOnce() {
        let (desk, _) = Self.desk()
        desk.candidates = LabLabelFieldTests.people
        desk.type("This is a memo for the website conductor.")
        desk.type("We need a second remote for the vault.")
        desk.type("No, the topic is X, Y, Z.")
        #expect(desk.transcript == "This is a memo for the website conductor. We need a second remote for the vault. No, the topic is X, Y, Z.")
        #expect(desk.board.recipient?.name == "Website Conductor")
        #expect(desk.board.isPinned("forWhom"))
        #expect(desk.board.values["topic"]?.text == "X, Y, Z")
        #expect(desk.overrides.map(\.field) == ["topic", "forWhom"])
        #expect(desk.overrides.first?.sentence == "No, the topic is X, Y, Z.")
    }

    @Test func aLoopsAnswerDoesNotMoveALabelPinnedWhileTheModelWasThinking() {
        let (desk, _) = Self.desk()
        desk.type("We need a second remote for the vault.")
        // The answer arrives after the person has spoken.
        desk.type("The title is Remotes.")
        desk.take(LabLabelLoopTests.record([("setTitle", "Second remote"), ("setTopic", "Vaults")]), number: 1,
                  window: "We need a second remote for the vault.", transcript: desk.transcript, fields: desk.inUse)
        #expect(desk.board.values["title"]?.text == "Remotes")
        #expect(desk.board.values["topic"]?.text == "Vaults")
        #expect(desk.lastChanged == ["topic"])
        #expect(desk.loops.first?.proposals.map(\.outcome) == [.pinned, .changed])
        desk.setByHand("topic", "Sync")
        #expect(desk.board.values["topic"] == LabLabelValue(text: "Sync", source: "hand", loop: nil, matched: nil))
        desk.unpin("topic")
        #expect(!desk.board.isPinned("topic"))
    }

    @Test func theChoicesAreKeptAndTheFourCannotBeSwitchedOff() {
        let (desk, defaults) = Self.desk()
        #expect(desk.inUse.map(\.id) == ["forWhom", "topic", "title", "urgency", "kind", "nextAction"])
        #expect(desk.seconds == 5)
        #expect(desk.windowTokens == 1000)
        desk.setChosen("kind", false)
        desk.setChosen("project", true)
        desk.setChosen("topic", false)
        desk.seconds = 10
        desk.windowTokens = 0
        let reopened = LabLabelsDesk(defaults: defaults, host: LabActionHost())
        #expect(reopened.inUse.map(\.id) == ["forWhom", "topic", "title", "urgency", "nextAction", "project"])
        #expect(reopened.seconds == 10)
        #expect(reopened.windowTokens == 0)
    }

    @Test func itDoesNotListenWhileANoteIsBeingRecordedAndAsksNothingWithNoWords() async {
        let host = LabActionHost()
        host.isRecording = { true }
        let (desk, _) = Self.desk(host: host)
        await desk.start(localeId: "en-GB")
        #expect(!desk.running)
        #expect(desk.problem == "A note is being recorded. The Lab does not listen at the same time.")
        await desk.loop(force: true)
        #expect(desk.loops.isEmpty)
    }

    @Test func aNewNoteClearsTheLabelsAndTheLogSurvivesItsJSON() throws {
        let (desk, _) = Self.desk()
        desk.type("The topic is vaults.")
        desk.take(LabLabelLoopTests.record([("setTitle", "Second remote")]), number: 1, window: "The topic is vaults.",
                  transcript: desk.transcript, fields: desk.inUse)
        let json = desk.log.json
        #expect(json.contains("\"experiment\" : \"L04\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LabLabelLog.self, from: Data(json.utf8))
        #expect(back.board == desk.board)
        #expect(back.loops.map(\.number) == [1])
        #expect(back.overrides.map(\.value) == ["vaults"])
        desk.startAgain()
        #expect(desk.board == LabLabelBoard())
        #expect(desk.transcript.isEmpty)
        #expect(desk.overrides.isEmpty)
        #expect(desk.loops.count == 1)
        desk.clearLog()
        #expect(desk.loops.isEmpty)
    }
}
