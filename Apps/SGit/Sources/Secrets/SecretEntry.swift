import Foundation
import Security

/// One secret, kept as one encrypted JSON file in a vault's `secrets/` folder
/// (design: website/sgit-app/secrets/index.md). The vault encrypts it like any other file; this type
/// is what is inside. A personal secrets vault and a team vault hold the same files.
struct SecretEntry: Codable, Equatable, Identifiable, Sendable {
    static let format = "sgit.ai/secret/v1"
    static let folder = "secrets"

    struct Field: Codable, Equatable, Hashable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var value: String
        /// Hidden until Face ID, and copied with an expiry.
        var hidden: Bool
    }

    var format = SecretEntry.format
    var id: String
    var kind: SecretKindOfEntry
    var name: String
    var fields: [Field]
    var note: String
    var createdAt: Date
    var updatedAt: Date
    /// The signing key id of the device that last changed it, so a screen can say "this device" or "another".
    var changedBy: String?

    var path: String { Self.path(for: id) }
    static func path(for id: String) -> String { "\(folder)/\(id).json" }

    static func isSecretPath(_ path: String) -> Bool {
        path.hasPrefix(folder + "/") && path.hasSuffix(".json") && !path.dropFirst(folder.count + 1).contains("/")
    }

    /// A new entry of a kind, with that kind's empty fields.
    static func new(_ kind: SecretKindOfEntry, at date: Date = Date()) -> SecretEntry {
        SecretEntry(id: UUID().uuidString.lowercased(), kind: kind, name: "",
                    fields: kind.template.map { Field(label: $0.label, value: "", hidden: $0.hidden) },
                    note: "", createdAt: date, updatedAt: date, changedBy: nil)
    }

    /// The fields worth keeping: those with something in them.
    var filled: [Field] { fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    /// What a list shows under the name, never a hidden value.
    var subtitle: String {
        if let shown = fields.first(where: { !$0.hidden && !$0.value.isEmpty }) { return shown.value }
        return kind.words
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SecretEntry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(SecretEntry.self, from: data)
        guard entry.format == format else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not \(format)")) }
        return entry
    }
}

/// The kinds of secret, each with the fields it starts with.
enum SecretKindOfEntry: String, Codable, CaseIterable, Sendable, Identifiable {
    case login, device, wifi, card, note, token, vaultKey, readKey, accessKey, recoveryCode

    var id: String { rawValue }

    var words: String {
        switch self {
        case .login: return "Login"
        case .device: return "Device passcode"
        case .wifi: return "Wi-Fi"
        case .card: return "Card"
        case .note: return "Secure note"
        case .token: return "API key or token"
        case .vaultKey: return "Vault key"
        case .readKey: return "Read key"
        case .accessKey: return "Server access key"
        case .recoveryCode: return "Recovery codes"
        }
    }

    var symbol: String {
        switch self {
        case .login: return "person.badge.key"
        case .device: return "laptopcomputer.and.iphone"
        case .wifi: return "wifi"
        case .card: return "creditcard"
        case .note: return "note.text"
        case .token: return "chevron.left.forwardslash.chevron.right"
        case .vaultKey: return "lock.square.stack"
        case .readKey: return "eye.square"
        case .accessKey: return "server.rack"
        case .recoveryCode: return "lifepreserver"
        }
    }

    var template: [(label: String, hidden: Bool)] {
        switch self {
        case .login: return [("Website", false), ("Username", false), ("Password", true), ("One-time code secret", true)]
        case .device: return [("Device", false), ("Who uses it", false), ("Passcode", true)]
        case .wifi: return [("Network", false), ("Password", true)]
        case .card: return [("Name on card", false), ("Number", true), ("Expires", false), ("Security code", true), ("PIN", true)]
        case .note: return [("Note", true)]
        case .token: return [("Service", false), ("Token", true)]
        case .vaultKey: return [("Vault key", true)]
        case .readKey: return [("Read key", true)]
        case .accessKey: return [("Server", false), ("Access key", true)]
        case .recoveryCode: return [("Service", false), ("Codes", true)]
        }
    }

    /// Whether "Make a strong password" is offered for this kind.
    var takesGeneratedPassword: Bool { [.login, .device, .wifi].contains(self) }
}

/// Strong passwords, from the system's random source.
enum PasswordMaker {
    /// Letters and digits without the ones that are easily confused (0 O o 1 l I).
    static let alphabet = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Groups of `groupSize` characters joined by hyphens: easy to read aloud and to type on a television.
    static func make(groups: Int = 4, groupSize: Int = 5) -> String {
        let count = groups * groupSize
        var bytes = [UInt8](repeating: 0, count: count * 2)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        var out: [Character] = []
        var index = 0
        while out.count < count, index + 1 < bytes.count {
            // Two bytes per character, rejecting the top of the range so that every character is equally likely.
            let value = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2
            let limit = 65_536 - 65_536 % alphabet.count
            if value < limit { out.append(alphabet[value % alphabet.count]) }
        }
        if out.count < count { return make(groups: groups, groupSize: groupSize) }
        return stride(from: 0, to: count, by: groupSize).map { String(out[$0..<$0 + groupSize]) }.joined(separator: "-")
    }
}
