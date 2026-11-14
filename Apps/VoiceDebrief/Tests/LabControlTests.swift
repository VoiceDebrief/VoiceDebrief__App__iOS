import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Lab L02: the fixed phrases")
struct LabTriggerTests {
    static func match(_ text: String) -> LabControlProposal? {
        LabTriggerMatcher.match(text, triggers: LabTrigger.defaults)?.proposal
    }

    @Test func aPhraseProposesItsActionWithWhatFollowsAsTheArgument() {
        #expect(Self.match("Send this to Maria.") == LabControlProposal(action: "sendTo", argument: "maria"))
        #expect(Self.match("Please record for five minutes") == LabControlProposal(action: "recordFor", argument: "five minutes"))
        #expect(Self.match("Find the note about the boiler.") == LabControlProposal(action: "findNote", argument: "the boiler"))
        #expect(Self.match("Open the library.") == LabControlProposal(action: "openSection", argument: "library"))
    }

    @Test func anActionWithNoArgumentTakesNone() {
        #expect(Self.match("OK, stop recording now please") == LabControlProposal(action: "finishRecording", argument: ""))
        #expect(Self.match("Save this to my vault.") == LabControlProposal(action: "saveToVault", argument: ""))
        #expect(Self.match("Cancel that.") == LabControlProposal(action: "cancelLast", argument: ""))
    }

    @Test func aRefusalProposesNothing() {
        #expect(Self.match("Do not send it now.") == nil)
        #expect(Self.match("Don't stop recording") == nil)
        #expect(Self.match("Never send this to Maria") == nil)
    }

    @Test func wordsThatHoldNoPhraseProposeNothing() {
        #expect(Self.match("She said she would send the report to Maria on Friday.") == nil)
        #expect(Self.match("I think the meeting went well.") == nil)
        #expect(Self.match("") == nil)
        // The whole phrase, word for word: resend is not send.
        #expect(Self.match("resend now") == nil)
    }

    @Test func thePhrasesAloneAreFooledByAPhraseInPassing() {
        // Kept as a test sentence for that reason: it is what a model might do better.
        #expect(Self.match("The vault needs a second remote before we open the office.")?.action == "openSection")
    }

    @Test func theLongestPhraseWins() {
        let triggers = [LabTrigger(phrase: "send", action: "sendTo"), LabTrigger(phrase: "send now", action: "finishRecording")]
        #expect(LabTriggerMatcher.match("send now", triggers: triggers)?.proposal.action == "finishRecording")
    }

    @Test func theFirstListHoldsTheRecordingsOwnPhrases() {
        for phrase in VoiceCommand.phrases {
            #expect(LabTrigger.defaults.contains(LabTrigger(phrase: phrase, action: "finishRecording")))
        }
        #expect(LabTrigger.defaults.allSatisfy { LabAction(rawValue: $0.action) != nil })
    }
}

@Suite("Lab L02: sentences and states")
struct LabControlEntryTests {
    static let at = Date(timeIntervalSince1970: 1_794_650_000)

    static func entry(_ words: String, expected: String? = nil, askModel: Bool = false, automatic: Set<String> = []) -> LabControlEntry {
        LabControlEntry(id: "e", heardAt: at, words: words, source: "typed", expected: expected,
                        triggers: LabTrigger.defaults, askModel: askModel, automatic: automatic)
    }

    /// A door record in which one tool was called, made with the door's own recorder.
    static func record(calling name: String?, arguments: [String: String] = [:], error: ModelDoorError? = nil) -> ModelDoorRecord {
        let recorder = ModelDoorRecorder()
        if let name { _ = recorder.measure(tool: name, arguments: arguments) { LabControlToolkit.reply } }
        var record = ModelDoorRecord(startedAt: at, instructions: LabControlDefaults.instructions, prompt: "p",
                                     policy: ModelDoorPolicy(allowedTools: LabAction.allCases.map(\.rawValue)),
                                     toolsOffered: LabControlToolkit().definitions, toolsWithheld: [])
        record.toolCalls = recorder.toolCalls
        record.error = error
        record.totalMs = 800
        return record
    }

    @Test func onlyWhatSettledSinceLastTimeIsTaken() {
        let first = LabUtterances.fresh(settled: "Open the library. ", consumed: 0)
        #expect(first?.text == "Open the library.")
        #expect(first?.consumed == 18)
        #expect(LabUtterances.fresh(settled: "Open the library. ", consumed: 18) == nil)
        let second = LabUtterances.fresh(settled: "Open the library. Cancel that.", consumed: 18)
        #expect(second?.text == "Cancel that.")
        #expect(LabUtterances.fresh(settled: "Open the library.  ... ", consumed: 18) == nil)
    }

    @Test func aProposalWaitsAndNothingIsDoneUntilThePersonSaysSo() {
        var entry = Self.entry("Stop recording.")
        #expect(entry.state == .waiting)
        #expect(entry.chosen == nil)
        #expect(entry.truth == nil)
        entry.doIt(now: Self.at)
        #expect(entry.state == .done)
        #expect(entry.chosen?.action == "finishRecording")
        #expect(entry.phraseVerdict == true)
        // Done is final: a second answer changes nothing.
        entry.notThis()
        #expect(entry.state == .done)
    }

    @Test func notThisCountsAgainstWhoeverProposedIt() {
        var entry = Self.entry("The vault needs a second remote before we open the office.")
        entry.notThis(now: Self.at)
        #expect(entry.state == .notThis)
        #expect(entry.chosen == nil)
        #expect(entry.phraseVerdict == false)
    }

    @Test func aSentenceWithNoProposalRestsAndCanStillBeCorrected() {
        var entry = Self.entry("Could you take me to the settings?")
        #expect(entry.state == .nothing)
        #expect(entry.phraseVerdict == nil)
        entry.edit(action: "openSection", argument: "settings", now: Self.at)
        #expect(entry.state == .done)
        #expect(entry.edited)
        #expect(entry.chosen == LabControlProposal(action: "openSection", argument: "settings"))
        #expect(entry.phraseVerdict == false)
    }

    @Test func correctingToNoActionRefusesTheProposal() {
        var entry = Self.entry("Open the library.")
        entry.edit(action: LabAction.none, argument: "", now: Self.at)
        #expect(entry.state == .notThis)
        #expect(entry.truth == .action("none"))
        #expect(entry.phraseVerdict == false)
    }

    @Test func anActionMarkedAutomaticIsDoneAtOnceAndIsNotCountedAsAJudgement() {
        let entry = Self.entry("Stop recording.", automatic: ["finishRecording"])
        #expect(entry.state == .done)
        #expect(entry.automatic)
        #expect(entry.chosen?.action == "finishRecording")
        #expect(entry.truth == nil)
        // Only that action: another still waits.
        #expect(Self.entry("Open the library.", automatic: ["finishRecording"]).state == .waiting)
    }

    @Test func theModelsFirstToolCallIsItsProposalAndComesBeforeThePhrases() {
        var entry = Self.entry("Open the library.", askModel: true)
        #expect(entry.state == .asking)
        entry.doIt()
        entry.edit(action: "sendTo", argument: "x")
        #expect(entry.state == .asking)
        entry.receive(Self.record(calling: "findNote", arguments: ["words": "library"]), automatic: [])
        #expect(entry.state == .waiting)
        #expect(entry.model == LabControlProposal(action: "findNote", argument: "library"))
        #expect(entry.proposal?.action == "findNote")
        #expect(entry.phrase?.action == "openSection")
        #expect(entry.modelMs == 800)
    }

    @Test func aModelThatCallsNoToolLeavesThePhrasesProposal() {
        var entry = Self.entry("Open the library.", expected: "openSection", askModel: true)
        entry.receive(Self.record(calling: nil), automatic: [])
        #expect(entry.model == nil)
        #expect(entry.state == .waiting)
        #expect(entry.proposal?.action == "openSection")
        #expect(entry.modelVerdict == false)
        #expect(entry.phraseVerdict == true)
    }

    @Test func aModelErrorIsNotAJudgementOfTheModel() {
        var entry = Self.entry("I think the meeting went well.", expected: "none", askModel: true)
        entry.receive(Self.record(calling: nil, error: ModelDoorError(kind: "unavailable", words: "w", raw: "")), automatic: [])
        #expect(entry.state == .nothing)
        #expect(entry.modelVerdict == nil)
        #expect(entry.phraseVerdict == true)
    }

    @Test func theTallyCountsRightWrongMissedAndErrors() {
        var right = Self.entry("Cancel that.", expected: "cancelLast", askModel: true)
        right.receive(Self.record(calling: "cancelLast"), automatic: [])
        var wrong = Self.entry("Cancel that.", expected: "cancelLast", askModel: true)
        wrong.receive(Self.record(calling: "finishRecording"), automatic: [])
        var missed = Self.entry("Could you take me to the settings?", expected: "openSection", askModel: true)
        missed.receive(Self.record(calling: nil), automatic: [])
        var failed = Self.entry("Cancel that.", expected: "cancelLast", askModel: true)
        failed.receive(Self.record(calling: nil, error: ModelDoorError(kind: "guardrail", words: "w", raw: "")), automatic: [])
        let unjudged = Self.entry("Cancel that.")
        let tally = LabControlTally.of([right, wrong, missed, failed, unjudged])
        #expect(tally.modelJudged == 3)
        #expect(tally.modelRight == 1)
        #expect(tally.modelWrongAction == 1)
        #expect(tally.modelMissed == 1)
        #expect(tally.modelErrors == 1)
        #expect(tally.modelMeanMs == 800)
        #expect(tally.phraseJudged == 4)
        #expect(tally.phraseRight == 3)
    }

    @Test func theTestSentencesAreDistinctNameRealActionsAndHoldNothingToCopy() {
        #expect(Set(LabControlTest.all.map(\.words)).count == LabControlTest.all.count)
        #expect(LabControlTest.all.allSatisfy { $0.expected == LabAction.none || LabAction(rawValue: $0.expected) != nil })
        #expect(LabControlTest.all.contains { $0.expected == LabAction.none })
        for text in LabAction.allCases.map(\.summary) + [LabControlDefaults.instructions] {
            #expect(!text.contains("\""))
        }
        #expect(LabControlToolkit().definitions.map(\.name) == LabAction.allCases.map(\.rawValue))
    }
}

@Suite("Lab L02: the control centre")
@MainActor
struct LabControlCentreTests {
    static func centre() -> LabControlCentre {
        let centre = LabControlCentre(defaults: UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!)
        centre.askModel = false
        return centre
    }

    @Test func aSentenceBecomesACardThatWaits() throws {
        let centre = Self.centre()
        let id = try #require(centre.hear("  Send this to Maria.  ", source: "typed"))
        #expect(centre.hear("   ", source: "typed") == nil)
        #expect(centre.entries.count == 1)
        #expect(centre.entries[0].words == "Send this to Maria.")
        #expect(centre.entries[0].state == .waiting)
        centre.doIt(id)
        #expect(centre.entries[0].state == .done)
        #expect(centre.entries[0].chosen == LabControlProposal(action: "sendTo", argument: "maria"))
    }

    @Test func thePhrasesAreThePersonsOwnAndAreKept() {
        let defaults = UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!
        let centre = LabControlCentre(defaults: defaults)
        centre.askModel = false
        #expect(centre.triggers == LabTrigger.defaults)
        centre.addTrigger(phrase: "  Wrap it UP! ", action: "finishRecording")
        centre.addTrigger(phrase: "wrap it up", action: "cancelLast")
        #expect(centre.triggers.filter { $0.phrase == "wrap it up" }.count == 1)
        centre.hear("That is enough, wrap it up.", source: "typed")
        #expect(centre.entries[0].phrase?.action == "finishRecording")

        let reopened = LabControlCentre(defaults: defaults)
        #expect(reopened.triggers.last == LabTrigger(phrase: "wrap it up", action: "finishRecording"))
        reopened.removeTriggers(at: IndexSet(integer: reopened.triggers.count - 1))
        #expect(reopened.triggers == LabTrigger.defaults)
        reopened.removeTriggers(at: IndexSet(integer: 0))
        reopened.restoreTriggers()
        #expect(LabControlCentre(defaults: defaults).triggers == LabTrigger.defaults)
    }

    @Test func whatRunsWithoutAskingIsKeptAndApplied() {
        let defaults = UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!
        let centre = LabControlCentre(defaults: defaults)
        centre.askModel = false
        centre.setAutomatic("cancelLast", true)
        centre.hear("Cancel that.", source: "typed")
        centre.hear("Open the library.", source: "typed")
        #expect(centre.entries.map(\.state) == [.waiting, .done])
        #expect(LabControlCentre(defaults: defaults).automatic == ["cancelLast"])
        centre.setAutomatic("cancelLast", false)
        #expect(LabControlCentre(defaults: defaults).automatic.isEmpty)
    }

    @Test func theTestSentencesRunThroughThePhrasesAndTheLogSurvivesItsJSON() async throws {
        let centre = Self.centre()
        await centre.runTests()
        #expect(centre.entries.count == LabControlTest.all.count)
        #expect(centre.entries.allSatisfy { $0.source == "test" && !$0.modelAsked })
        let tally = LabControlTally.of(centre.entries)
        #expect(tally.modelJudged == 0)
        #expect(tally.phraseJudged == LabControlTest.all.count)
        // Eight said in a fixed phrase and three plain remarks are right; four paraphrases are
        // missed and one phrase in passing fools them.
        #expect(tally.phraseRight == 11)

        let json = centre.log.json
        #expect(json.contains("\"experiment\" : \"L02\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LabControlLog.self, from: Data(json.utf8))
        #expect(back.entries.map(\.words) == centre.entries.map(\.words))
        #expect(back.entries.map(\.state) == centre.entries.map(\.state))
        #expect(back.triggers == LabTrigger.defaults)
        centre.clear()
        #expect(centre.entries.isEmpty)
    }
}

@Suite("Lab L02: the two actions that are carried out")
@MainActor
struct LabControlActionTests {
    static func centre(host: LabActionHost) -> LabControlCentre {
        let centre = LabControlCentre(defaults: UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!, host: host)
        centre.askModel = false
        return centre
    }

    @Test func aSectionIsNamedByTheFirstWordThatIsOne() {
        #expect(LabSections.name(in: "library") == "library")
        #expect(LabSections.name(in: "the Settings, please") == "settings")
        #expect(LabSections.name(in: "office") == nil)
        #expect(LabSections.name(in: "library", names: ["record"]) == nil)
    }

    @Test func nothingIsOpenedUntilThePersonSaysDoIt() throws {
        let host = LabActionHost()
        var opened: [String] = []
        host.openSection = { name in
            opened.append(name)
            return name == "library"
        }
        let centre = Self.centre(host: host)
        let id = try #require(centre.hear("Open the library.", source: "typed"))
        #expect(opened.isEmpty)
        #expect(centre.entries[0].outcome == nil)
        centre.doIt(id)
        #expect(opened == ["library"])
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: true, words: "Opened library."))
        // Taken up once only.
        centre.doIt(id)
        centre.edit(id, action: "openSection", argument: "library")
        #expect(opened == ["library"])
    }

    @Test func notThisOpensNothing() throws {
        let host = LabActionHost()
        var opened = 0
        host.openSection = { _ in
            opened += 1
            return true
        }
        let centre = Self.centre(host: host)
        let id = try #require(centre.hear("The vault needs a second remote before we open the office.", source: "typed"))
        centre.notThis(id)
        #expect(opened == 0)
        #expect(centre.entries[0].outcome == nil)
    }

    @Test func aSectionThatDoesNotExistOrAHostThatIsNotConnectedSaysSo() throws {
        let host = LabActionHost()
        let centre = Self.centre(host: host)
        let unwired = try #require(centre.hear("Open the library.", source: "typed"))
        centre.doIt(unwired)
        #expect(centre.entries[0].outcome?.carriedOut == false)
        #expect(centre.entries[0].outcome?.words == "Not opened: this build has not connected the Lab to the app's sections.")

        host.openSection = { _ in false }
        let refused = try #require(centre.hear("Open the settings.", source: "typed"))
        centre.doIt(refused)
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: false, words: "Not opened: there is no section called settings."))

        let unnamed = try #require(centre.hear("Open the office.", source: "typed"))
        centre.doIt(unnamed)
        #expect(centre.entries[0].outcome?.carriedOut == false)
        #expect(centre.entries[0].outcome?.words == "Not opened: no section is named in the words office.")
    }

    @Test func anActionSwitchedToGoAheadIsCarriedOutAtOnce() {
        let host = LabActionHost()
        var opened: [String] = []
        host.openSection = { name in
            opened.append(name)
            return true
        }
        let centre = Self.centre(host: host)
        centre.setAutomatic("openSection", true)
        centre.hear("Go to the vaults.", source: "typed")
        #expect(opened == ["vaults"])
        #expect(centre.entries[0].automatic)
        #expect(centre.entries[0].outcome?.carriedOut == true)
    }

    @Test func theOtherActionsAreRecordedOnly() throws {
        let centre = Self.centre(host: LabActionHost())
        let id = try #require(centre.hear("Send this to Maria.", source: "typed"))
        centre.doIt(id)
        #expect(centre.entries[0].outcome == .recordedOnly)
        #expect(LabAction.allCases.filter(\.isCarriedOut) == [.openSection, .findNote, .recordTo])
    }

    @Test func findingANoteReadsTheLibraryAndChangesNothing() throws {
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let boiler = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB",
                                               now: Date(timeIntervalSince1970: 1_794_500_000)))
        _ = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB",
                                      now: Date(timeIntervalSince1970: 1_794_580_000)))
        var run = boiler.run
        run.transcript = Transcript(localeId: "en-GB", lines: [
            TranscriptLine(startMs: 0, endMs: 2000, text: "The boilers were serviced on Tuesday."),
        ])
        store.update(boiler.id, run: run, processing: false)
        let before = store.notes

        let centre = Self.centre(host: LabActionHost())
        let unsearched = try #require(centre.hear("Find the note about the boiler.", source: "typed"))
        centre.doIt(unsearched)
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: false, words: "Not searched: there is no library here."))

        centre.store = store
        let found = try #require(centre.hear("Find the note about the boiler.", source: "typed"))
        centre.doIt(found)
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: true, words: "Found 1: The boilers were serviced on Tuesday."))

        let none = try #require(centre.hear("Find the note about the entitlement.", source: "typed"))
        centre.doIt(none)
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: true, words: "Searched: no note holds entitlement."))

        let empty = try #require(centre.hear("Find the note about", source: "typed"))
        centre.doIt(empty)
        #expect(centre.entries[0].outcome?.carriedOut == false)
        #expect(store.notes == before)
    }

    @Test func aSearchWantsEveryWordAndTakesNewestFirst() {
        let notes = [
            LabNote(id: "a", createdAt: Date(timeIntervalSince1970: 100), title: "Boiler quote", transcript: "The plumber quoted for the boiler."),
            LabNote(id: "b", createdAt: Date(timeIntervalSince1970: 200), title: "Recording", transcript: "Ask the plumber about the kitchen tap."),
            LabNote(id: "c", createdAt: Date(timeIntervalSince1970: 300), title: "Recording", transcript: nil),
        ]
        #expect(LabNoteSearch.find("the plumber", in: notes).map(\.id) == ["b", "a"])
        #expect(LabNoteSearch.find("plumber boiler", in: notes).map(\.id) == ["a"])
        #expect(LabNoteSearch.find("the note about", in: notes).isEmpty)
        #expect(LabNoteSearch.find("garden", in: notes).isEmpty)
    }
}

@Suite("Lab L02: recording a note for someone")
@MainActor
struct LabControlRecordToTests {
    @Test func thePhrasesNameThePerson() {
        #expect(LabTriggerTests.match("Record a note for Maria.") == LabControlProposal(action: "recordTo", argument: "maria"))
        #expect(LabTriggerTests.match("Start recording for Claude") == LabControlProposal(action: "recordTo", argument: "claude"))
        // Recording for a time is a different action.
        #expect(LabTriggerTests.match("Record for five minutes.")?.action == "recordFor")
    }

    @Test func itAlwaysWaitsForDoItEvenIfSomeoneTriesToSwitchItOn() {
        let host = LabActionHost()
        var asked: [String] = []
        host.startRecording = { name in
            asked.append(name)
            return (true, "Recording, for Maria (sent when you finish).")
        }
        let centre = LabControlActionTests.centre(host: host)
        centre.setAutomatic("recordTo", true)
        #expect(centre.automatic.isEmpty)
        centre.hear("Record a note for Maria.", source: "typed")
        #expect(centre.entries[0].state == .waiting)
        #expect(asked.isEmpty)
        // Even a list that says otherwise does not let it through.
        let entry = LabControlEntry(id: "e", heardAt: Date(), words: "Record a note for Maria.", source: "typed",
                                    triggers: LabTrigger.defaults, askModel: false, automatic: ["recordTo"])
        #expect(entry.state == .waiting)
        #expect(LabAction.allCases.filter(\.alwaysAsks) == [.recordTo])
    }

    @Test func doItStartsTheRecordingOnceAndTheCardSaysWhatTheAppSaid() async throws {
        let host = LabActionHost()
        var asked: [String] = []
        host.startRecording = { name in
            asked.append(name)
            return (true, "Recording, for Maria (sent when you finish).")
        }
        let centre = LabControlActionTests.centre(host: host)
        let id = try #require(centre.hear("Record a note for Maria.", source: "typed"))
        centre.doIt(id)
        centre.doIt(id)
        await centre.pendingAction?.value
        #expect(asked == ["maria"])
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: true, words: "Recording, for Maria (sent when you finish)."))
    }

    @Test func aRefusalFromTheAppIsShownAndNothingIsClaimed() async throws {
        let host = LabActionHost()
        host.startRecording = { _ in (false, "Not started: there is no contact called maria.") }
        let centre = LabControlActionTests.centre(host: host)
        let id = try #require(centre.hear("Record a note for Maria.", source: "typed"))
        centre.doIt(id)
        await centre.pendingAction?.value
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: false, words: "Not started: there is no contact called maria."))
    }

    @Test func withNothingConnectedOrNoOneNamedNothingStarts() async throws {
        let centre = LabControlActionTests.centre(host: LabActionHost())
        let unwired = try #require(centre.hear("Record a note for Maria.", source: "typed"))
        centre.doIt(unwired)
        await centre.pendingAction?.value
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: false, words: "Not started: this build has not connected the Lab to recording."))

        let unnamed = try #require(centre.hear("Record a note for", source: "typed"))
        centre.doIt(unnamed)
        await centre.pendingAction?.value
        #expect(centre.entries[0].outcome == LabOutcome(carriedOut: false, words: "Not started: no one was named."))
    }

    @Test func aCorrectionMadeAfterwardsInTheLogCarriesNothingOut() async throws {
        let host = LabActionHost()
        var asked = 0
        host.startRecording = { _ in
            asked += 1
            return (true, "Recording.")
        }
        let centre = LabControlActionTests.centre(host: host)
        // Nothing was proposed, so there is no card: saying later what it asked for only judges it.
        let later = try #require(centre.hear("I want to say something new to Maria.", source: "typed"))
        #expect(centre.entries[0].state == .nothing)
        centre.edit(later, action: "recordTo", argument: "maria")
        await centre.pendingAction?.value
        #expect(asked == 0)
        #expect(centre.entries[0].state == .done)
        #expect(centre.entries[0].outcome == .correctedLater)

        // A card that is waiting, corrected to another person, does go ahead: that is the confirmation.
        let waiting = try #require(centre.hear("Record a note for Mario.", source: "typed"))
        centre.edit(waiting, action: "recordTo", argument: "Maria")
        await centre.pendingAction?.value
        #expect(asked == 1)
        #expect(centre.entries[0].outcome?.carriedOut == true)
    }
}

@Suite("Lab L02: listening keeps out of a recording's way")
@MainActor
struct LabControlListeningTests {
    @Test func itDoesNotListenWhileANoteIsBeingRecorded() async {
        let host = LabActionHost()
        host.isRecording = { true }
        let centre = LabControlActionTests.centre(host: host)
        await centre.startListening(localeId: "en-GB")
        #expect(!centre.listening)
        #expect(centre.problem == "A note is being recorded. The Lab does not listen at the same time.")
    }

    @Test func withNoLanguageChosenItSaysSoAndDoesNotListen() async {
        let centre = LabControlActionTests.centre(host: LabActionHost())
        await centre.startListening(localeId: "")
        #expect(!centre.listening)
        #expect(centre.problem == "Choose the language spoken in Settings first.")
        // A stop with nothing to stop is harmless and adds nothing to the log.
        await centre.stopListening()
        #expect(centre.entries.isEmpty)
    }
}

@Suite("Lab L02: a card says how the words became the action")
@MainActor
struct LabControlFlowTests {
    @Test func sentencesAreNumberedInTheOrderTheyWereHeard() {
        let centre = LabControlActionTests.centre(host: LabActionHost())
        centre.hear("Open the library.", source: "typed")
        centre.hear("I think the meeting went well.", source: "typed")
        centre.hear("Cancel that.", source: "typed")
        #expect(centre.entries.map(\.number) == [3, 2, 1])
        centre.clear()
        centre.hear("Cancel that.", source: "typed")
        #expect(centre.entries.map(\.number) == [1])
    }

    @Test func eachEngineIsDescribedInWords() {
        let heard = LabControlEntryTests.entry("Go to the vaults.")
        #expect(LabControlWords.phrase(heard) == "Open a section: vaults, from the phrase go to the")
        #expect(LabControlWords.model(heard) == "Not asked")
        #expect(LabControlWords.phrase(LabControlEntryTests.entry("I think the meeting went well.")) == "No phrase heard")

        var asked = LabControlEntryTests.entry("Go to the vaults.", askModel: true)
        #expect(LabControlWords.model(asked) == "Being asked")
        asked.receive(LabControlEntryTests.record(calling: "openSection", arguments: ["section": "vaults"]), automatic: [])
        #expect(LabControlWords.model(asked) == "Open a section: vaults, in 0.8 s")

        var silent = LabControlEntryTests.entry("Go to the vaults.", askModel: true)
        silent.receive(LabControlEntryTests.record(calling: nil), automatic: [])
        #expect(LabControlWords.model(silent) == "No action, in 0.8 s")

        var failed = LabControlEntryTests.entry("Go to the vaults.", askModel: true)
        failed.receive(LabControlEntryTests.record(calling: nil, error: ModelDoorError(kind: "unavailable", words: "Apple Intelligence is switched off in Settings.", raw: "")), automatic: [])
        #expect(LabControlWords.model(failed) == "Could not answer: Apple Intelligence is switched off in Settings.")
    }
}
