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
              detail: "Creates, reads and writes sgit vaults and derives a passkey's door.",
              status: .built),
        Stage(id: "record",
              title: "Record or open a voice note",
              detail: "Record here, with the words as you speak, or choose an audio file. Sharing from WhatsApp, and its Ogg Opus files, are not built.",
              status: .testing),
        Stage(id: "transcript",
              title: "Transcript, on this device",
              detail: "Apple's speech model, with the time of every line.",
              status: .testing),
        Stage(id: "debrief",
              title: "Debrief, on this device",
              detail: "Key points, actions and one sentence, written by Apple's on-device model.",
              status: .testing),
        Stage(id: "library",
              title: "A library on this device",
              detail: "Every recording is kept the moment it stops, with its transcript and debrief, and can be reopened.",
              status: .testing),
        Stage(id: "keep",
              title: "Keeping a debrief in a vault",
              detail: "Create a vault, save a debrief into it as one signed commit, and look inside. Vault keys are kept in iCloud Keychain by default, so your other devices can open your vaults; a switch keeps them on this device only.",
              status: .testing),
        Stage(id: "credit",
              title: "Credit that counts down",
              detail: "A balance charged a little for just about everything you do, kept on this device, allowed below zero. The top-up is simulated: no money is taken. Paying through the App Store is not built.",
              status: .testing),
        Stage(id: "account",
              title: "Your account, opened by a passkey",
              detail: "One passkey, one identity, and a recovery code.",
              status: .proposed),
        Stage(id: "vault-sync",
              title: "The same debriefs on every device",
              detail: "Opened by the passkey on your iPhone and iPad, with a library of what you have kept.",
              status: .proposed),
    ]

    static func stages(_ status: StageStatus) -> [Stage] {
        stages.filter { $0.status == status }
    }
}
