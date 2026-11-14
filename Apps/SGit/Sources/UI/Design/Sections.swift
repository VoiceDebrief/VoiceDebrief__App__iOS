import SwiftUI

/// The parts of SGit Vaults, each with one title, symbol, colour, drawing and line, used alike
/// wherever the part is shown or linked (website/design/identity).
enum SGSection: String, CaseIterable, Identifiable {
    case vaults, gallery, share, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vaults: "Vaults"
        case .gallery: "Gallery"
        case .share: "Share"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .vaults: "lock.shield"
        case .gallery: "square.grid.2x2"
        case .share: "link"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

    var line: String {
        switch self {
        case .vaults: "Folders of files with a history, encrypted on this device"
        case .gallery: "Vaults to show somebody, opened inside the app"
        case .share: "Give someone a key to read, or to read and add"
        case .history: "Every change, who made it and when"
        case .settings: "The server, this device and the log"
        }
    }

    var tint: Color {
        switch self {
        case .vaults: DS.Palette.indigo
        case .gallery: Color(dsHex: 0xE07A3F)
        case .share: Color(dsHex: 0xE5577E)
        case .history: Color(dsHex: 0x13A8C8)
        case .settings: Color(dsHex: 0x8A9BB0)
        }
    }

    /// The drawing in the asset catalogue (drawn by tools/art).
    var art: String { "SGArt-\(rawValue)" }
}
