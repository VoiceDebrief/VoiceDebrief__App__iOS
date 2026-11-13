import Foundation

/// The website's schedule picks (`nr.schedule.v1`), as kept in the reader vault at
/// `apps/agenda/picks.json` (promptugal.news assets/schedule/schedule.js, `__vault.save('agenda/picks')`).
///
///     {"v":1,"picks":[{"id":"events/<slug>","at":"2025-11-09T01:00:00.123Z"}]}
///
/// Merge rule (the website's `fromVault`): union by `id`; when both sides hold an id, the vault's
/// entry is kept. `at` is kept exactly as given (the website writes an ISO string, older copies a number).
public enum VaultPicks {
    public static let path = "apps/agenda/picks.json"

    /// The union of the vault's document and the local one, written in the website's member order
    /// (`v`, then `picks`; each pick `id`, `at`, then any other members by name), compact like `JSON.stringify`.
    /// A malformed vault document throws rather than being overwritten.
    public static func union(vault: Data?, local: Data) throws -> Data {
        var out: [[String: JSONValue]] = []
        var seen: Set<String> = []
        let vaultPicks = try picks(vault, label: "vault picks")
        let localPicks = try picks(local, label: "local picks")
        for pick in vaultPicks + localPicks {
            guard case .string(let id)? = pick["id"], !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(pick)
        }
        return Data(serialize(out).utf8)
    }

    /// The ids in a document, in order (for tests and the debug panel).
    public static func ids(_ data: Data) throws -> [String] {
        try picks(data, label: "picks").compactMap { if case .string(let id)? = $0["id"] { id } else { nil } }
    }

    static func picks(_ data: Data?, label: String) throws -> [[String: JSONValue]] {
        guard let data, !data.isEmpty else { return [] }
        guard let doc = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let members) = doc else {
            throw VaultError.malformed(path: path, detail: "\(label) are not a JSON object")
        }
        guard let list = members["picks"] else { return [] }
        guard case .array(let items) = list else {
            throw VaultError.malformed(path: path, detail: "\(label): `picks` is not a list")
        }
        return items.compactMap { if case .object(let pick) = $0 { pick } else { nil } }
    }

    static func serialize(_ picks: [[String: JSONValue]]) -> String {
        let items = picks.map { pick -> String in
            let rest = pick.keys.filter { $0 != "id" && $0 != "at" }.sorted()
            let ordered = ["id", "at"].filter { pick[$0] != nil } + rest
            return "{" + ordered.map { CanonicalJSON.serialize(.string($0)) + ":" + CanonicalJSON.serialize(pick[$0]!) }
                .joined(separator: ",") + "}"
        }
        return "{\"v\":1,\"picks\":[" + items.joined(separator: ",") + "]}"
    }
}

/// Append lanes: one new file per message, so writers on different devices never conflict.
public enum VaultLanes {
    /// `<UTC yyyyMMddTHHmmssZ>-<device>-<suffix>.json`, e.g. `20261107T061000Z-device-ab12cd34-9f3a.json`.
    /// Names sort by time. `suffix` is random unless given (tests).
    public static func fileName(at date: Date = Date(), device: String, suffix: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let safeDevice = String(device.lowercased().map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
        let tail = suffix ?? String(UUID().uuidString.lowercased().prefix(4))
        return "\(formatter.string(from: date))-\(safeDevice)-\(tail).json"
    }

    /// The path for a new file in `folder`.
    public static func path(folder: String, name: String) -> String {
        let trimmed = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return trimmed.isEmpty ? name : trimmed + "/" + name
    }
}
