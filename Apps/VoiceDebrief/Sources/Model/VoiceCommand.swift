import Foundation

/// Words that end a recording without a tap, for when the phone is out of reach (the owner, driving,
/// 14 November 2026: "I should be able to say send this now"). Heard in the live words; matched only at
/// the very end of what has been said, so the phrase inside a sentence does not stop anything.
enum VoiceCommand: Equatable, Sendable {
    case finish

    static let phrases = ["send this now", "send it now", "send now", "stop recording", "finish recording", "end recording"]

    /// The command the words so far end with, if any.
    static func detect(_ text: String) -> VoiceCommand? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let tail = words.suffix(4).joined(separator: " ")
        for phrase in phrases where tail.hasSuffix(phrase) {
            // The whole phrase, not the end of a longer word ("resend now" is not "send now").
            let pw = phrase.split(separator: " ").map(String.init)
            guard Array(words.suffix(pw.count)) == pw else { continue }
            // "don't send it now" is not a command (the owner, driving, 14 November 2026).
            let before = words.dropLast(pw.count).suffix(2)
            if before.contains("not") || before.contains("never") || before.last == "t" && before.first == "don" || before.last == "dont" { return nil }
            return .finish
        }
        return nil
    }
}
