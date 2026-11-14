import SwiftUI

/// The parts of SGit Vaults, each with one title, symbol, colour, drawing and line, used alike
/// wherever the part is shown or linked (website/design/identity). Some are per vault (share,
/// history, webVault); people, you, contacts, inbox and secrets are the people session's, behind
/// one home row (`PeopleHome`).
enum SGSection: String, CaseIterable, Identifiable {
    case vaults, gallery, share, history, webVault, settings, activity
    case people, you, contacts, inbox, secrets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vaults: "Vaults"
        case .gallery: "Gallery"
        case .share: "Share"
        case .history: "History"
        case .webVault: "Web Vault"
        case .settings: "Settings"
        case .activity: "Your activity"
        case .people: "People"
        case .you: "You"
        case .contacts: "Contacts"
        case .inbox: "Inbox"
        case .secrets: "Secrets"
        }
    }

    var symbol: String {
        switch self {
        case .vaults: "lock.shield"
        case .gallery: "square.grid.2x2"
        case .share: "link"
        case .history: "clock.arrow.circlepath"
        case .webVault: "globe"
        case .settings: "gearshape"
        case .activity: "chart.bar"
        case .people: "person.2"
        case .you: "person.badge.key"
        case .contacts: "person.crop.circle"
        case .inbox: "tray"
        case .secrets: "key"
        }
    }

    var line: String {
        switch self {
        case .vaults: "Folders of files with a history, encrypted on this device"
        case .gallery: "Vaults to show somebody, opened inside the app"
        case .share: "Give someone a key to read, or to read and add"
        case .history: "Every change, who made it and when"
        case .webVault: "The whole web Vault, inside the app"
        case .settings: "The server, this device and the log"
        case .activity: "What you have used; send it"
        case .people: "You, your contacts, what came in, your secrets"
        case .you: "Your keys and your devices"
        case .contacts: "The people you share with"
        case .inbox: "What others have sent you"
        case .secrets: "Keys and passwords, kept encrypted"
        }
    }

    var tint: Color {
        switch self {
        case .vaults: DS.Palette.indigo
        case .gallery: Color(dsHex: 0xE07A3F)
        case .share: Color(dsHex: 0xE5577E)
        case .history: Color(dsHex: 0x13A8C8)
        case .webVault: DS.Palette.indigo
        case .settings: Color(dsHex: 0x8A9BB0)
        case .activity: Color(dsHex: 0xF08A4B)
        case .people, .contacts: Color(dsHex: 0xE5577E)
        case .you, .secrets: Color(dsHex: 0x8E5CF7)
        case .inbox: Color(dsHex: 0x2F80ED)
        }
    }

    /// The drawing in the asset catalogue (drawn by tools/art).
    var art: String { "SGArt-\(rawValue)" }
}
