import Foundation

/// Where one piece of the app stands. Built means it is in this build and proven; testing means the
/// code is in this build but nobody has yet judged it on a real device; proposed means it does not exist.
enum StageStatus: String, Sendable, CaseIterable {
    case built
    case testing
    case proposed

    var label: String {
        switch self {
        case .built: return "Built"
        case .testing: return "In test"
        case .proposed: return "Proposed"
        }
    }
}

/// One piece of the app, as the status screen lists it.
struct Stage: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
    let status: StageStatus
}

/// What this build holds and what it does not. This list is the app's own reality file: a stage is
/// marked built only in the commit that builds it.
enum Roadmap {
    static let stages: [Stage] = [
        Stage(id: "skeleton",
              title: "The app and its build",
              detail: "An iPhone and iPad app that compiles, tests and reports its version.",
              status: .built),
        Stage(id: "vault-engine",
              title: "The vault engine",
              detail: "Reads and writes sgit vaults and derives a passkey's door. In the app, not yet used by a screen.",
              status: .built),
        Stage(id: "record",
              title: "Record or open a voice note",
              detail: "Record here or choose an audio file. Sharing from WhatsApp, and its Ogg Opus files, are not built.",
              status: .testing),
        Stage(id: "transcript",
              title: "Transcript, on this device",
              detail: "Apple's speech model, with the time of every line.",
              status: .testing),
        Stage(id: "debrief",
              title: "Debrief, on this device",
              detail: "Key points, actions and one sentence, written by Apple's on-device model.",
              status: .testing),
        Stage(id: "keep",
              title: "Keeping a debrief",
              detail: "Nothing is saved yet: a result lasts until the app closes.",
              status: .proposed),
        Stage(id: "account",
              title: "Your account, opened by a passkey",
              detail: "One passkey, one identity, and a recovery code.",
              status: .proposed),
        Stage(id: "vault-sync",
              title: "Your debriefs in your own vault",
              detail: "Encrypted on this device before anything is sent, and the same on your iPhone and iPad.",
              status: .proposed),
    ]

    static func stages(_ status: StageStatus) -> [Stage] {
        stages.filter { $0.status == status }
    }
}
