import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Lab L07: the change between two texts")
struct LabDiffTests {
    static func show(_ before: String, _ after: String) -> String {
        LabDiff.words(before, after).map { piece in
            switch piece.kind {
            case .same: return piece.text
            case .removed: return "[-\(piece.text)-]"
            case .added: return "{+\(piece.text)+}"
            }
        }.joined()
    }

    @Test func wordsThatGoAndWordsThatComeInAreMarked() {
        #expect(Self.show("The boiler is very old.", "The boiler is old.") == "The boiler is [-very -]old.")
        #expect(Self.show("Call the plumber", "Call the plumber on Tuesday") == "Call the plumber {+on Tuesday+}")
        #expect(Self.show("We met maria silva.", "We met Maria Silva.") == "We met [-maria silva.-]{+Maria Silva.+}")
    }

    @Test func theSameTextAndEmptyTextsAreHandled() {
        #expect(LabDiff.words("One two.", "One two.") == [LabDiffPiece(kind: .same, text: "One two.")])
        #expect(LabDiff.words("", "").isEmpty)
        #expect(LabDiff.words("", "New.") == [LabDiffPiece(kind: .added, text: "New.")])
        #expect(LabDiff.words("Old.", "") == [LabDiffPiece(kind: .removed, text: "Old.")])
        // Spacing alone is not a change.
        #expect(LabDiff.words("One  two.\n", "One two.").allSatisfy { $0.kind == .same })
    }

    @Test func puttingThePiecesBackGivesEachText() {
        let before = "I spoke to the plumber, who said the boiler is very old and will need replacing soon."
        let after = "The plumber said the boiler is old and needs replacing."
        let pieces = LabDiff.words(before, after)
        #expect(pieces.filter { $0.kind != .added }.map(\.text).joined().split(separator: " ") == before.split(separator: " "))
        #expect(pieces.filter { $0.kind != .removed }.map(\.text).joined() == after)
        #expect(LabDiff.count(.added, in: pieces) + LabDiff.count(.same, in: pieces) == LabDiff.tokens(after).count)
        #expect(LabDiff.tokens("One two\nthree  ") == ["One ", "two\n", "three  "])
    }
}

@Suite("Lab L07: the request and the proposal")
struct LabEditTurnTests {
    static let at = Date(timeIntervalSince1970: 1_794_744_000)

    @Test func thePromptHoldsTheRequestTheNamesAndTheText() {
        #expect(LabEditPrompt.prompt(request: " Make it shorter. ", text: "The boiler is very old.", names: []) == "Request: Make it shorter.\nText:\nThe boiler is very old.")
        #expect(LabEditPrompt.prompt(request: "Fix the names.", text: "We met maria.", names: ["Maria Silva", "Claude (developer)"])
                == "Request: Fix the names.\nNames that may be meant: Maria Silva, Claude (developer).\nText:\nWe met maria.")
        let long = String(repeating: "word ", count: 1000)
        #expect(LabEditPrompt.prompt(request: "x", text: long, names: []).count == "Request: x\nText:\n".count + LabEditPrompt.longest)
        for text in LabEditPrompt.presets + [LabEditPrompt.instructions] {
            #expect(!text.contains("\""))
        }
        #expect(LabNoToolkit().definitions.isEmpty)
    }

    @Test func wrappingAroundAReplyIsTakenOffAndNothingInsideIsTouched() {
        #expect(LabEditPrompt.tidy("  The boiler is old.\n") == "The boiler is old.")
        #expect(LabEditPrompt.tidy("\"The boiler is old.\"") == "The boiler is old.")
        #expect(LabEditPrompt.tidy("```\n- one\n- two\n```") == "- one\n- two")
        #expect(LabEditPrompt.tidy("```markdown\n- one\n```") == "- one")
        // Quotation marks that belong to the text stay.
        #expect(LabEditPrompt.tidy("\"Old\", he said, \"very old.\"") == "\"Old\", he said, \"very old.\"")
        #expect(LabEditPrompt.tidy("He said \"old\".") == "He said \"old\".")
    }

    @Test func aProposalWaitsAndIsAcceptedOrRejectedOnce() {
        var turn = LabEditTurn(number: 1, at: Self.at, request: "Make it shorter.", before: "The boiler is very old.")
        turn.propose("\"The boiler is old.\"")
        #expect(turn.state == .proposed)
        #expect(turn.after == "The boiler is old.")
        #expect(turn.tidied)
        #expect(turn.wordsBefore == 5)
        #expect(turn.wordsAfter == 4)
        #expect(turn.wordsRemoved == 1)
        #expect(turn.wordsAdded == 0)
        #expect(turn.cautions == ["A code fence or quotation marks around the reply were taken off."])
        #expect(turn.notice == "Edit 1: no model, 5 words to 4, 1 out and 0 in")
        turn.accept(now: Self.at)
        turn.reject()
        #expect(turn.state == .accepted)
    }

    @Test func thingsToKnowBeforeAcceptingAreSaid() {
        var same = LabEditTurn(number: 1, at: Self.at, request: "Fix the grammar.", before: "The boiler is old.")
        same.propose("The boiler is old.")
        #expect(same.cautions == ["Nothing was changed."])

        var longer = LabEditTurn(number: 2, at: Self.at, request: "Make it more formal.", before: "The boiler is old.")
        longer.propose("It has come to our attention that the boiler in question is of considerable age.")
        #expect(longer.cautions == ["The proposed text is more than twice as long."])

        let twenty = (1...24).map { "word\($0)" }.joined(separator: " ")
        var gutted = LabEditTurn(number: 3, at: Self.at, request: "Make it shorter.", before: twenty)
        gutted.propose("word1 word2.")
        #expect(gutted.cautions == ["The proposed text is less than a quarter of the length: check that nothing needed has gone."])

        var empty = LabEditTurn(number: 4, at: Self.at, request: "Make it shorter.", before: "The boiler is old.")
        empty.propose("   ")
        #expect(empty.state == .failed)
        #expect(empty.cautions.isEmpty)
        #expect(empty.notice == "Edit 4: the model gave no text (no model)")
        empty.accept()
        #expect(empty.state == .failed)
    }
}

@Suite("Lab L07: the desk owns the text")
@MainActor
struct LabEditDeskTests {
    @Test func theTextChangesOnlyWhenAProposalIsAcceptedAndCanBePutBack() throws {
        let desk = LabEditDesk()
        desk.text = "The boiler is very old."
        var turn = desk.begin("Make it shorter.", before: desk.text)
        turn.propose("The boiler is old.")
        desk.add(turn)
        #expect(desk.waiting?.number == 1)
        #expect(desk.text == "The boiler is very old.")
        desk.accept(1)
        #expect(desk.text == "The boiler is old.")
        #expect(desk.waiting == nil)
        desk.accept(1)
        desk.reject(1)
        #expect(desk.turns[0].state == .accepted)
        desk.undo(1)
        #expect(desk.text == "The boiler is very old.")

        var second = desk.begin("Make it more formal.", before: desk.text)
        second.propose("The boiler is of considerable age.")
        desk.add(second)
        desk.reject(2)
        #expect(desk.text == "The boiler is very old.")
        #expect(desk.turns.map(\.state) == [.rejected, .accepted])
    }

    @Test func aProposalMadeFromATextThatHasSinceChangedIsNotApplied() {
        let desk = LabEditDesk()
        desk.text = "The boiler is very old."
        var turn = desk.begin("Make it shorter.", before: desk.text)
        turn.propose("The boiler is old.")
        desk.add(turn)
        desk.text = "Something else entirely."
        desk.accept(1)
        #expect(desk.text == "Something else entirely.")
        #expect(desk.turns[0].state == .rejected)
    }

    @Test func aTextTooLongToSendWholeSaysSoAndTheLogSurvivesItsJSON() async throws {
        let desk = LabEditDesk()
        desk.text = String(repeating: "word ", count: 1000)
        var turn = desk.begin("Make it shorter.", before: desk.text)
        #expect(turn.cut)
        turn.propose("word word.")
        #expect(turn.cautions.first?.hasPrefix("The text was too long to send whole.") == true)
        desk.add(turn)
        let json = desk.log.json
        #expect(json.contains("\"experiment\" : \"L07\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LabEditLog.self, from: Data(json.utf8))
        #expect(back.turns.map(\.after) == ["word word."])
        #expect(back.turns.map(\.pieces) == desk.turns.map(\.pieces))
        desk.clear()
        #expect(desk.turns.isEmpty)
        // Nothing is asked of the model with no text or no request.
        desk.text = "   "
        await desk.propose("Make it shorter.")
        desk.text = "Words."
        await desk.propose("   ")
        #expect(desk.turns.isEmpty)
    }
}
