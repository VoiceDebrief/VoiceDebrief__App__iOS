import Testing
@testable import VoiceDebrief

/// A send that fails (poor signal while driving) is tried five times in all, further apart each time.
struct SendRetryTests {
    @Test func fiveTriesFurtherApart() {
        #expect(SendRetry.attempts == 5)
        #expect(SendRetry.wait(before: 2) == 10)
        #expect(SendRetry.wait(before: 3) == 30)
        #expect(SendRetry.wait(before: 4) == 60)
        #expect(SendRetry.wait(before: 5) == 120)
        #expect(SendRetry.wait(before: 6) == nil)
        #expect(SendRetry.wait(before: 1) == nil)
    }
}
