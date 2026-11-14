import Foundation

/// The one way out of the Lab into the rest of the app. Whoever owns the app's sections sets
/// `openSection`; until then nothing can be opened and the card says so.
@MainActor
final class LabActionHost {
    static let shared = LabActionHost()

    /// Given a section's name in lower case, shows it and returns true, or returns false if there is
    /// no such section.
    var openSection: ((String) -> Bool)?
    /// The names `openSection` accepts. Empty means not said: the Lab's own list is used.
    var sectionNames: [String] = []
}
