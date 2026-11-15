import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Words spoken into a field")
struct DictationTextTests {
    @Test func anEmptyFieldTakesTheWords() {
        #expect(DictationText.join("", " hello there ") == "hello there")
    }

    @Test func spokenWordsFollowWhatWasTyped() {
        #expect(DictationText.join("Call", "Sam tomorrow") == "Call Sam tomorrow")
        #expect(DictationText.join("Call ", "Sam") == "Call Sam")
        #expect(DictationText.join("Line one\n", "line two") == "Line one\nline two")
    }

    @Test func nothingSaidLeavesTheFieldAsItWas() {
        #expect(DictationText.join("Typed", "") == "Typed")
        #expect(DictationText.join("Typed", "   ") == "Typed")
    }
}
