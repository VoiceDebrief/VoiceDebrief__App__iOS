import Foundation

/// Reads the Web Summit team CRM's vault layout (as its schemas/ describe it, 16 November 2026):
/// `companies/<slug>/company.json`, `contacts/<slug>/contact.json`, `actions/<date>-<slug>.json`.
/// A contact becomes a candidate, with its company's name, its stage and its next step; a plain action
/// that names a contact gives that contact a next step. Sealed files (`ws-crm-env-1`: `recipients`,
/// `iv`, `ct`) open only with a recipient's private key, which this app does not hold: they are counted
/// and listed, never guessed at. Every value keeps where it came from.
enum TeamCRMReader {
    enum Place: Equatable {
        case company, contact, action, thread
    }

    static func place(of path: String) -> Place? {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last, name.hasSuffix(".json") else { return nil }
        if parts.count >= 3, parts[parts.count - 3] == "companies", name == "company.json" { return .company }
        if parts.count >= 3, parts[parts.count - 3] == "contacts", name == "contact.json" { return .contact }
        if parts.count >= 2, parts[parts.count - 2] == "actions" { return .action }
        if parts.count >= 4, parts[parts.count - 3] == "comms", name == "thread.json" { return .thread }
        return nil
    }

    struct Result {
        var candidates: [ContactCandidate] = []
        var skipped: [ImportScanner.Skipped] = []
        var sealed = 0
        var companies = 0
        /// Paths this reader took, so no other reader looks at them.
        var taken: Set<String> = []
    }

    static func isSealed(_ object: [String: Any]) -> Bool {
        object["ct"] != nil && object["recipients"] != nil
    }

    static func read(_ files: [(path: String, data: Data)], file prefix: String, at: Date) -> Result {
        var result = Result()
        var companyNames: [String: String] = [:]   // id or slug to name
        var contacts: [(path: String, object: [String: Any])] = []
        var actions: [(path: String, object: [String: Any])] = []

        for (path, data) in files {
            guard let spot = place(of: path) else { continue }
            result.taken.insert(path)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.skipped.append(.init(path: path, reason: "not a JSON object"))
                continue
            }
            if isSealed(object) {
                result.sealed += 1
                result.skipped.append(.init(path: path, reason: "sealed to the team's keys: needs your private key on this device"))
                continue
            }
            switch spot {
            case .company:
                result.companies += 1
                if let name = object["name"] as? String {
                    let slug = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
                    companyNames[slug] = name
                    if let id = object["id"] as? String { companyNames[id] = name }
                }
            case .contact: contacts.append((path, object))
            case .action: actions.append((path, object))
            case .thread: result.skipped.append(.init(path: path, reason: "an email or call thread: not imported yet"))
            }
        }

        var byID: [String: Int] = [:]
        for (path, object) in contacts {
            let name = string(object["name"]) ?? ""
            var c = ContactCandidate(name: name, source: Source(saidBy: string(object["updated_by"]).map { "The team CRM, last changed by \($0)" } ?? "The team CRM",
                                                                at: date(object["updated_at"]) ?? at,
                                                                from: "\(prefix)/\(path)",
                                                                note: string(object["source"])))
            c.emails = (string(object["email"]).map { [$0] } ?? []).filter(ContactKeys.isEmail)
            c.phones = string(object["phone"]).map { [$0] } ?? []
            if let company = string(object["company"]) ?? string(object["organisation"]) {
                c.organisation = companyNames[company] ?? company
            }
            c.role = string(object["role"])
            c.links = [string(object["linkedin"])].compactMap { $0 }
            let met = (object["met"] as? [String]) ?? []
            var notes: [String] = []
            if !met.isEmpty { notes.append("Met: " + met.joined(separator: ", ")) }
            if let by = string(object["met_by"]) { notes.append("Met by \(by)" + (string(object["met_at"]).map { " at \($0)" } ?? "")) }
            if let interest = string(object["interest"]) { notes.append("Interest: \(interest)") }
            if let prefers = string(object["prefers"]) { notes.append("Prefers: \(prefers)") }
            if let details = string(object["contact_details"]) { notes.append(details) }
            c.notes = notes
            let pipeline = object["pipeline"] as? [String: Any]
            c.stage = string(pipeline?["stage"])
            c.nextStep = string(object["next_step"]) ?? string(pipeline?["next"])
            c.owner = string(object["owner"])
            c.settleName()
            if c.isUsable {
                if let id = string(object["id"]) { byID[id] = result.candidates.count }
                result.candidates.append(c)
            } else {
                result.skipped.append(.init(path: path, reason: "a contact with no name, email or phone"))
            }
        }

        // A plain follow-up action that names a contact gives that contact its next step, when it has none.
        for (path, object) in actions {
            let state = (string(object["state"]) ?? "").lowercased()
            guard let contact = string(object["contact"]), let i = byID[contact], !["done", "closed", "cancelled"].contains(state) else {
                result.skipped.append(.init(path: path, reason: "an action not about one of these contacts"))
                continue
            }
            if result.candidates[i].nextStep == nil {
                result.candidates[i].nextStep = string(object["next_step"]) ?? string(object["title"])
                result.candidates[i].due = date(object["due"])
            }
        }
        return result
    }

    private static func string(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let full = ISO8601DateFormatter()
        if let d = full.date(from: s) { return d.toTheSecond }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d.toTheSecond }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: s)
    }
}

/// The stages of the team's pipeline (Angelo's design): free text in the team CRM, matched loosely here,
/// and always kept as written.
enum PipelineStage {
    static let known = ["to contact", "to follow up", "in conversation", "call booked", "proposal", "won", "parked"]

    /// What a follow-up's status is for a stage written as text.
    static func status(for text: String?) -> FollowUp.Status {
        let t = (text ?? "").lowercased()
        if t.contains("won") || t.contains("done") { return .done }
        if t.contains("parked") || t.contains("dropped") || t.contains("lost") { return .dropped }
        return .open
    }
}

/// A vault that lists other vaults (`crm-sources`): `index.json` names them, `keys/<name>.json` holds
/// each one's vault key. The keys are read into memory for this import only, never stored or shown.
enum VaultOfVaults {
    struct Child: Hashable, Identifiable, Sendable {
        var name: String
        var label: String
        var vaultID: String
        var keyText: String
        var id: String { name }
    }

    static func children(_ files: [(path: String, data: Data)]) -> [Child] {
        guard let index = files.first(where: { $0.path == "index.json" }),
              let root = (try? JSONSerialization.jsonObject(with: index.data)) as? [String: Any],
              let listed = root["vaults"] as? [[String: Any]] else { return [] }
        var out: [Child] = []
        for entry in listed {
            guard let name = entry["name"] as? String,
                  let keyFile = files.first(where: { $0.path == "keys/\(name).json" }),
                  let key = (try? JSONSerialization.jsonObject(with: keyFile.data)) as? [String: Any],
                  let text = key["vault_key"] as? String else { continue }
            out.append(Child(name: name, label: (entry["label"] as? String) ?? name,
                             vaultID: (entry["vault_id"] as? String) ?? "", keyText: text))
        }
        return out
    }
}
