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
        if isPlumbing(path) { return nil }
        if RecordFiles.parse(path: path)?.0 == .person { return .crmRecord }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "vcf", "vcard": return .vCard
        case "csv": return .csv
        case "json": return .json
        default: return photoExtensions.contains(ext) ? .photo : nil
        }
    }

    /// A vault's own workings, never contacts: its schemas, derived graphs, key files, links to other
    /// vaults, its app and its index.
    static func isPlumbing(_ path: String) -> Bool {
        let first = path.split(separator: "/").first.map(String.init) ?? ""
        let name = (path as NSString).lastPathComponent
        return ["schemas", "graph", "keys", ".vault", "assets"].contains(first)
            || ["app.json", "index.json", "package.json"].contains(name) || name.hasSuffix(".link.json") || name.hasSuffix(".schema.json")
    }

    /// Reads the files given (path and bytes). `vault` names the vault in each source.
    static func scan(_ files: [(path: String, data: Data)], vault: String, at: Date) -> Result {
        var result = Result()
        let twin = TwinReader.read(files, file: vault, at: at)
        let rest = files.filter { !twin.taken.contains($0.path) }
        let team = TeamCRMReader.read(rest, file: vault, at: at)
        result.candidates = twin.candidates + team.candidates
        result.skipped = twin.skipped + team.skipped
        for (path, data) in rest where !team.taken.contains(path) {
            guard let fileKind = kind(of: path) else { continue }
            let file = "\(vault)/\(path)"
            let text = String(decoding: data, as: UTF8.self)
            let found: [ContactCandidate]
            switch fileKind {
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
                result.skipped.append(Skipped(path: path, reason: fileKind == .json || fileKind == .csv ? "no column or key that names a person" : "nothing that reads as a contact"))
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
