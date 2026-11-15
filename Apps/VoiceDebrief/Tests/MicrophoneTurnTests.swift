import Foundation
import Testing
@testable import VoiceDebrief

@Suite("One listener at a time")
@MainActor
struct MicrophoneTurnTests {
    @Test func oneHolderAtATime() {
        let turn = MicrophoneTurn()
        let field = UUID(), lab = UUID()
        #expect(turn.take(field))
        #expect(!turn.take(lab))
        #expect(turn.take(field))
        turn.giveBack(field)
        #expect(turn.take(lab))
    }

    @Test func onlyTheHolderCanGiveItBack() {
        let turn = MicrophoneTurn()
        let field = UUID(), lab = UUID()
        #expect(turn.take(field))
        turn.giveBack(lab)
        #expect(turn.holder == field)
        #expect(!turn.take(lab))
    }
}
