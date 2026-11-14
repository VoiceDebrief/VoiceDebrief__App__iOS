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
        // Seven said in a fixed phrase and three plain remarks are right; three paraphrases are
        // missed and one phrase in passing fools them.
        #expect(tally.phraseRight == 10)

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
