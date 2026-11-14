import CryptoKit
import Foundation

/// Who an avatar stands for, which sets its frame: a conductor must stand out among agents.
enum AvatarKind: String, Sendable, CaseIterable {
    case me, person, conductor, session, subagent

    /// From an agent's `kind` in the agents report; anything unknown is drawn as a session.
    init(agentKind: String) {
        switch agentKind.lowercased() {
        case "conductor": self = .conductor
        case "subagent", "sub-agent": self = .subagent
        default: self = .session
        }
    }

    var isAgent: Bool { self == .conductor || self == .session || self == .subagent }
}

/// The choices that make one generated character, worked out from a stable id (a key fingerprint,
/// an agent id, or "me"), so the same id always draws the same character on every device.
/// `variant` gives the same id another look, for a person who wants a different one.
struct AvatarSeed: Equatable, Sendable {
    /// The palette the characters are painted from (sRGB hex), bright enough on navy and on white.
    static let palette: [UInt32] = [
        0x0E9E72, 0x2F80ED, 0xE5577E, 0x4F5BD5, 0x8E5CF7, 0xD4A12A,
        0xF08A4B, 0x13A8C8, 0x2BB39A, 0xC94FD6, 0xE5484D, 0x5B8DEF,
    ]
    static let shapes = 4, eyeStyles = 4, mouthStyles = 4

    let colour: Int
    let accent: Int
    let shape: Int
    let eyes: Int
    let mouth: Int

    init(id: String, variant: Int = 0) {
        let b = Array(SHA256.hash(data: Data("\(id)#\(variant)".utf8)))
        let n = Self.palette.count
        colour = Int(b[0]) % n
        shape = Int(b[1]) % Self.shapes
        eyes = Int(b[2]) % Self.eyeStyles
        mouth = Int(b[3]) % Self.mouthStyles
        // Never the same as the main colour, nor its neighbours: 3 to 8 steps round the palette.
        accent = (colour + 3 + Int(b[4]) % 6) % n
    }
}

/// The line under a group of recipients: "Sam", "Sam and Ana", "Sam, Ana and 3 more".
enum RouteNames {
    static func line(_ names: [String], shown: Int = 2) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let first = names.prefix(shown).joined(separator: ", ")
            let more = names.count - shown
            return more == 1 ? "\(first) and \(names[shown])" : "\(first) and \(more) more"
        }
    }
}
