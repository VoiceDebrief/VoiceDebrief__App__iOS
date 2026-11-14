import Foundation

/// What to tell a person when they open the app: what is new since they last looked (issue 025).
/// Worked out by the code from the library, not written by a model, so it is always true. The model may
/// later phrase it; it will not decide it.
struct Briefing: Equatable, Sendable {
    var lines: [String]
    var upgradedTo: String?

    var isEmpty: Bool { lines.isEmpty && upgradedTo == nil }

    static func make(notes: [Note], since lastOpened: Date?, lastVersion: String?, version: String, now: Date = Date()) -> Briefing {
        var lines: [String] = []
        let upgraded = (lastVersion != nil && lastVersion != version) ? version : nil
        guard let lastOpened else { return Briefing(lines: [], upgradedTo: upgraded) }

        let new = notes.filter { $0.createdAt > lastOpened }
        if !new.isEmpty {
            let minutes = new.compactMap(\.run.audioSeconds).reduce(0, +) / 60
            let length = minutes >= 1 ? ", \(Int(minutes.rounded())) min in all" : ""
            lines.append(new.count == 1 ? "1 new note since you last looked\(length)." : "\(new.count) new notes since you last looked\(length).")
        }
        let interrupted = notes.filter { $0.processing }
        if !interrupted.isEmpty {
            lines.append(interrupted.count == 1
                ? "1 note was interrupted: its recording is kept; open it to run it again."
                : "\(interrupted.count) notes were interrupted: their recordings are kept; open them to run them again.")
        }
        let sent = notes.flatMap { $0.sends ?? [] }.filter { $0.at > lastOpened }
        if !sent.isEmpty {
            let names = Array(Set(sent.map(\.to))).sorted()
            lines.append("Sent \(sent.count == 1 ? "1 note" : "\(sent.count) notes") to \(names.joined(separator: ", ")).")
        }
        let saved = notes.flatMap { $0.saves ?? [] }.filter { $0.at > lastOpened }
        if !saved.isEmpty {
            lines.append("Saved \(saved.count == 1 ? "1 note" : "\(saved.count) notes") to your vault.")
        }
        let unsent = notes.filter { $0.sendProblem != nil }
        if !unsent.isEmpty {
            lines.append(unsent.count == 1 ? "1 note could not be sent: open it to try again." : "\(unsent.count) notes could not be sent: open them to try again.")
        }
        let unsaved = notes.filter { $0.saveProblem != nil }
        if !unsaved.isEmpty {
            lines.append(unsaved.count == 1 ? "1 note could not be saved to a vault: open it to see why." : "\(unsaved.count) notes could not be saved to a vault: open them to see why.")
        }
        return Briefing(lines: lines, upgradedTo: upgraded)
    }
}
