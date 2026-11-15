import Foundation

/// Whose turn it is to listen, or to speak. One part of the app uses the audio at a time (the owner,
/// 15 November 2026: "one listener for the whole app"): a text field's dictation, the Lab's control
/// centre (L02), its live labels (L04), and anything that speaks aloud (L05 Talk back), so that nothing
/// starts listening in the middle of an answer. Each takes the turn before it starts and gives it back
/// when it stops, however it stops. A voice note being recorded is kept apart by each one's own check.
@MainActor
final class MicrophoneTurn {
    static let shared = MicrophoneTurn()

    /// Who holds the turn now, if anyone.
    private(set) var holder: UUID?

    init() {}

    /// Takes the turn for `who`; true if it is now theirs (or already was).
    func take(_ who: UUID) -> Bool {
        if holder == nil || holder == who {
            holder = who
            return true
        }
        return false
    }

    /// Gives the turn back, if `who` holds it; anyone else giving it back changes nothing.
    func giveBack(_ who: UUID) {
        if holder == who { holder = nil }
    }

    static let busy = "Something else in the app is listening or speaking. Stop it first."
}
