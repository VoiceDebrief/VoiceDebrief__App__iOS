import SwiftUI

/// Every part of the app has one title, one symbol, one colour, one picture and one line, used
/// alike by the tab bar, the sidebar, the record screen's tiles and the section's own header.
extension RootTab: CaseIterable, Identifiable {
    static var allCases: [RootTab] {
        [.record, .library, .contacts, .vaults, .agents, .guide, .identity, .credit, .activity, .lab, .words, .about, .settings]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Record"
        case .library: "Library"
        case .contacts: "Contacts"
        case .vaults: "Vaults"
        case .agents: "Agents"
        case .guide: "Guide"
        case .identity: "Identity"
        case .credit: "Credit"
        case .activity: "Your activity"
        case .lab: "Lab"
        case .words: "Your words"
        case .about: "What this build does"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .record: "mic.fill"
        case .library: "tray.full"
        case .contacts: "person.2"
        case .vaults: "lock.shield"
        case .agents: "person.3"
        case .guide: "book"
        case .identity: "person.badge.key"
        case .credit: "sterlingsign.circle"
        case .activity: "chart.bar"
        case .lab: "flask"
        case .words: "character.book.closed"
        case .about: "checklist"
        case .settings: "gearshape"
        }
    }

    /// One line saying what is there, for a tile.
    var line: String {
        switch self {
        case .record: "A voice note in, a transcript and a debrief out"
        case .library: "Every note, by day"
        case .contacts: "Who notes go to; add one by QR code"
        case .vaults: "Encrypted copies that you own"
        case .agents: "Who is working for you; talk to them"
        case .guide: "What is new, every idea, how things work"
        case .identity: "Your keys and your devices"
        case .credit: "What each thing costs"
        case .activity: "What you have used; send it"
        case .lab: "Try Apple's model, tools on and off"
        case .words: "Names the clean text should know"
        case .about: "Built, in test, not built"
        case .settings: "Language, saving, diagnostics"
        }
    }

    var tint: Color {
        switch self {
        case .record: DS.Palette.green
        case .library: Color(dsHex: 0x2F80ED)
        case .contacts: Color(dsHex: 0xE5577E)
        case .vaults: DS.Palette.indigo
        case .agents: Color(dsHex: 0xC94FD6)
        case .guide: Color(dsHex: 0x2BA3D9)
        case .identity: Color(dsHex: 0x8E5CF7)
        case .credit: Color(dsHex: 0xD4A12A)
        case .activity: Color(dsHex: 0xF08A4B)
        case .lab: Color(dsHex: 0x13A8C8)
        case .words: Color(dsHex: 0x2BB39A)
        case .about: Color(dsHex: 0x12C08A)
        case .settings: Color(dsHex: 0x8A9BB0)
        }
    }

    /// The section's drawing in the asset catalogue (drawn by tools/art).
    var art: String { "VDArt-\(rawValue)" }
}
