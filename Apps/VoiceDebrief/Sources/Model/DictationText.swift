import Foundation

/// What a text field holds while it is being dictated into: what was there before, then what has
/// been said so far, with one space between and none doubled.
enum DictationText {
    static func join(_ before: String, _ spoken: String) -> String {
        let said = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return before }
        guard !before.isEmpty else { return said }
        let separator = before.last.map { $0.isWhitespace } == true ? "" : " "
        return before + separator + said
    }
}
