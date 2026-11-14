import Foundation

/// The one mark a note's row may carry (the design: "at most one mark: working, something wrong,
/// or saved to a vault"), in a word or two. Worked out from the note, never guessed.
enum NoteMark: Equatable, Sendable {
    /// Being transcribed, debriefed or sent now.
    case working(String)
    /// Kept, but not finished: interrupted, or no words found.
    case degraded(String)
    /// Something the person asked for did not happen: a send or a save to a vault.
    case failed(String)
    /// Saved into a vault; the vault's name.
    case inVault(String)
    case none

    /// In order: what is happening now, then what went wrong, then what is unfinished, then where it is kept.
    static func of(_ note: Note, working: String?) -> NoteMark {
        if let working, !working.isEmpty { return .working(working) }
        if note.sendProblem != nil { return .failed(note.pendingSend.map { "Not sent to \($0.name)" } ?? "Not sent") }
        if note.saveProblem != nil { return .failed("Not saved to the vault") }
        if note.processing { return .degraded("Interrupted") }
        if note.run.transcript == nil || note.run.transcript?.isEmpty == true { return .degraded("No words found") }
        if let save = note.saves?.last { return .inVault(save.vaultName) }
        return .none
    }
}
