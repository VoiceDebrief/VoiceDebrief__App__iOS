import Foundation

// The SGit CRM record format, version 1 (`sgit.ai/crm/v1`), written down at website/crm/format/.
// One JSON file per record, in a folder named for its kind, so that two devices rarely touch the
// same file. Every value can say where it came from; a record says who made it and who last changed
// it, and an agent always names its key.

enum CRMFormat {
    static let version = "sgit.ai/crm/v1"
}

/// The seven kinds of record, each in its own folder of the vault.
enum RecordKind: String, Codable, CaseIterable, Sendable {
    case person
    case organisation
    case interaction
    case introduction
    case followUp = "follow-up"
    case draft
    case play

    /// The vault folder this kind is kept in.
    var folder: String {
        switch self {
        case .person: return "people"
        case .organisation: return "organisations"
        case .interaction: return "interactions"
        case .introduction: return "introductions"
        case .followUp: return "follow-ups"
        case .draft: return "drafts"
        case .play: return "plays"
        }
    }

    init?(folder: String) {
        guard let kind = RecordKind.allCases.first(where: { $0.folder == folder }) else { return nil }
        self = kind
    }
}

/// Who made a change or said a thing: a person, an agent (with its key) or an import.
struct Actor: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case person, agent, `import`
    }

    var kind: Kind
    /// A display name: "Dinis", "crm.capture@sgit.dinis", "Import of contacts.vcf".
    var name: String
    /// The fingerprint of the key that signed the change. Required for an agent.
    var key: String?

    static func person(_ name: String, key: String? = nil) -> Actor { Actor(kind: .person, name: name, key: key) }
    static func agent(_ name: String, key: String) -> Actor { Actor(kind: .agent, name: name, key: key) }
    static func importer(_ name: String) -> Actor { Actor(kind: .import, name: name, key: nil) }
}

/// When and by whom.
struct Stamp: Codable, Hashable, Sendable {
    var at: Date
    var by: Actor
}

/// Where a value came from: who or what said it, when, and from where.
struct Source: Codable, Hashable, Sendable {
    /// Who or what said it: "Dinis, in conversation", "Vision text on a badge photo".
    var saidBy: String
    var at: Date
    /// Where: "Web Summit 2026, Centre Stage", "vault 8f3a.../contacts.vcf, card 3".
    var from: String
    var note: String?

    enum CodingKeys: String, CodingKey {
        case saidBy = "said_by", at, from, note
    }
}

/// A value with its own source. Without one, the record's source stands for it.
struct Sourced<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: Value
    var source: Source?

    init(_ value: Value, source: Source? = nil) {
        self.value = value
        self.source = source
    }
}

/// What every record has, whatever its kind.
protocol CRMRecord: Codable, Hashable, Sendable, Identifiable where ID == String {
    static var kind: RecordKind { get }
    var format: String { get }
    var id: String { get }
    var created: Stamp { get }
    var changed: Stamp { get set }
    /// Where the record as a whole came from.
    var source: Source { get }
    /// Problems particular to this kind.
    func kindProblems() -> [String]
}

extension CRMRecord {
    /// The record's path in the vault: `people/<id>.json`.
    var path: String { "\(Self.kind.folder)/\(id).json" }

    /// Everything wrong with the record. Empty when it may be written.
    func problems() -> [String] {
        var found: [String] = []
        if format != CRMFormat.version { found.append("format is \(format), expected \(CRMFormat.version)") }
        if !RecordID.isValid(id) { found.append("id \(id) is not a lowercase UUID") }
        for (label, stamp) in [("created", created), ("changed", changed)] {
            if stamp.by.kind == .agent && (stamp.by.key ?? "").isEmpty {
                found.append("\(label) by the agent \(stamp.by.name), which names no key")
            }
        }
        if changed.at < created.at { found.append("changed before it was created") }
        if source.saidBy.isEmpty || source.from.isEmpty { found.append("the source says neither who nor where") }
        return found + kindProblems()
    }
}

enum RecordID {
    static func make() -> String { UUID().uuidString.lowercased() }

    static func isValid(_ id: String) -> Bool {
        UUID(uuidString: id) != nil && id == id.lowercased() && id.count == 36
    }
}

extension Date {
    /// Record times are kept to the second, as ISO 8601 writes them, so a record reads back equal.
    var toTheSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
}

extension Stamp {
    static func now(by actor: Actor) -> Stamp { Stamp(at: Date().toTheSecond, by: actor) }
}
