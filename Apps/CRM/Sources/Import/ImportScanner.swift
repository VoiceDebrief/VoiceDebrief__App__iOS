import Foundation

/// Looks through the files of a vault for what may be contacts, and reads each with the right reader.
/// Photos are listed, not read: their text is read on the device by `CardPhotoReader`, which is
/// asynchronous and needs Vision.
enum ImportScanner {
    enum FileKind: Equatable, Sendable {
        case crmRecord, vCard, csv, json, photo
    }

    /// A file looked at that held nothing usable, and why.
    struct Skipped: Hashable, Sendable {
        var path: String
        var reason: String
    }

    struct Result: Sendable {
        var candidates: [ContactCandidate] = []
        var photos: [String] = []
        /// Files looked at that held nothing usable, with why.
        var skipped: [Skipped] = []
    }

    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]

    /// What a path might hold, from its name alone; nil for files the import ignores.
    static func kind(of path: String) -> FileKind? {
        if RecordFiles.parse(path: path)?.0 == .person { return .crmRecord }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "vcf", "vcard": return .vCard
        case "csv": return .csv
        case "json": return .json
        default: return photoExtensions.contains(ext) ? .photo : nil
        }
    }

    /// Reads the files given (path and bytes). `vault` names the vault in each source.
    static func scan(_ files: [(path: String, data: Data)], vault: String, at: Date) -> Result {
        var result = Result()
        for (path, data) in files {
            guard let kind = kind(of: path) else { continue }
            let file = "\(vault)/\(path)"
            let text = String(decoding: data, as: UTF8.self)
            let found: [ContactCandidate]
            switch kind {
            case .photo:
                result.photos.append(path)
                continue
            case .crmRecord:
                if case .person(let p)? = try? RecordFiles.decode(path: path, data: data) {
                    found = [candidate(from: p, file: file)]
                } else {
                    found = []
                }
            case .vCard: found = VCardReader.read(text, file: file, at: at)
            case .csv: found = TableReader.readCSV(text, file: file, at: at)
            case .json: found = TableReader.readJSON(data, file: file, at: at)
            }
            if found.isEmpty {
                result.skipped.append(Skipped(path: path, reason: kind == .json || kind == .csv ? "no column or key that names a person" : "nothing that reads as a contact"))
            }
            result.candidates += found
        }
        return result
    }

    /// A person already in the CRM format, from another vault, as a candidate.
    static func candidate(from p: Person, file: String) -> ContactCandidate {
        ContactCandidate(name: p.name.value, emails: p.emails.map(\.value), phones: p.phones.map(\.value),
                         organisation: nil, role: p.role?.value, links: p.links.map(\.value), notes: p.notes.map(\.value),
                         source: Source(saidBy: p.source.saidBy, at: p.source.at, from: "\(file) (from \(p.source.from))", note: p.source.note))
    }
}
