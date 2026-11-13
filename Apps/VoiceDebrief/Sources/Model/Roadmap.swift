import Foundation

/// Where one piece of the app stands. The words are the VoiceDebrief family's: built means it is in
/// this build and tested; proposed means it does not exist yet.
enum StageStatus: String, Sendable, CaseIterable {
    case built
    case proposed

    var label: String {
        switch self {
        case .built: return "Built"
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
              title: "Record or bring a voice note",
              detail: "Record here, or share a voice note from WhatsApp or Files.",
              status: .proposed),
        Stage(id: "transcript",
              title: "Transcript, on this device",
              detail: "Apple's speech models, with the time of every line.",
              status: .proposed),
        Stage(id: "debrief",
              title: "Debrief, on this device",
              detail: "Key points, actions and one sentence, written by Apple Intelligence.",
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
