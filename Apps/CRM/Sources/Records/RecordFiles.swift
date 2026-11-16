import Foundation

/// Any record, read from a file whose kind is only known from its folder.
enum AnyRecord: Hashable, Sendable {
    case person(Person)
    case organisation(Organisation)
    case interaction(Interaction)
    case introduction(Introduction)
    case followUp(FollowUp)
    case draft(Draft)
    case play(Play)

    var record: any CRMRecord {
        switch self {
        case .person(let r): return r
        case .organisation(let r): return r
        case .interaction(let r): return r
        case .introduction(let r): return r
        case .followUp(let r): return r
        case .draft(let r): return r
        case .play(let r): return r
        }
    }

    var kind: RecordKind { type(of: record).kind }
    var id: String { record.id }
    var path: String { record.path }
}

enum RecordFileError: LocalizedError, Equatable {
    case notARecordPath(String)
    case idMismatch(path: String, id: String)
    case invalid(path: String, problems: [String])

    var errorDescription: String? {
        switch self {
        case .notARecordPath(let p): return "\(p) is not where a CRM record is kept."
        case .idMismatch(let p, let id): return "\(p) holds the record \(id), not the one its name says."
        case .invalid(let p, let problems): return "\(p): " + problems.joined(separator: "; ")
        }
    }
}

/// Reads and writes record files. The encoding is stable (sorted keys, ISO 8601 dates, two-space
/// pretty printing as Foundation does it), so a record written twice is the same bytes and a vault's
/// history shows only what changed.
enum RecordFiles {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// The bytes for a record, refusing one with problems.
    static func encode<R: CRMRecord>(_ record: R) throws -> Data {
        let problems = record.problems()
        guard problems.isEmpty else { throw RecordFileError.invalid(path: record.path, problems: problems) }
        var data = try encoder().encode(record)
        data.append(0x0A)
        return data
    }

    /// The kind and id a path names: `people/<id>.json`.
    static func parse(path: String) -> (RecordKind, String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, let name = parts.last, name.hasSuffix(".json"),
              let kind = RecordKind(folder: parts[parts.count - 2]) else { return nil }
        let id = String(name.dropLast(5))
        return RecordID.isValid(id) ? (kind, id) : nil
    }

    static func decode(path: String, data: Data) throws -> AnyRecord {
        guard let (kind, id) = parse(path: path) else { throw RecordFileError.notARecordPath(path) }
        let d = decoder()
        let any: AnyRecord
        switch kind {
        case .person: any = .person(try d.decode(Person.self, from: data))
        case .organisation: any = .organisation(try d.decode(Organisation.self, from: data))
        case .interaction: any = .interaction(try d.decode(Interaction.self, from: data))
        case .introduction: any = .introduction(try d.decode(Introduction.self, from: data))
        case .followUp: any = .followUp(try d.decode(FollowUp.self, from: data))
        case .draft: any = .draft(try d.decode(Draft.self, from: data))
        case .play: any = .play(try d.decode(Play.self, from: data))
        }
        guard any.id == id else { throw RecordFileError.idMismatch(path: path, id: any.id) }
        let problems = any.record.problems()
        guard problems.isEmpty else { throw RecordFileError.invalid(path: path, problems: problems) }
        return any
    }
}
