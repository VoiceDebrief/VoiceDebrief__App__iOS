import Testing
@testable import VoiceDebrief

@Suite("Finishing a recording by voice")
struct VoiceCommandTests {
    @Test func thePhraseAtTheEndFinishes() {
        #expect(VoiceCommand.detect("so that is the plan. Send this now.") == .finish)
        #expect(VoiceCommand.detect("ok stop recording") == .finish)
        #expect(VoiceCommand.detect("Send it now") == .finish)
    }

    @Test func thePhraseInsideASentenceDoesNot() {
        #expect(VoiceCommand.detect("I will send this now and then talk about the vault") == nil)
        #expect(VoiceCommand.detect("please resend now") == nil)
        #expect(VoiceCommand.detect("") == nil)
    }
}
