import Foundation
import SGitVault

/// One vault worth showing: a name, a line about it, a topic, and the link that opens it.
/// The link is a secret when it carries a key, so entries are kept in the Keychain or read from a
/// vault, never written into the app.
struct GalleryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String { link }
    var name: String
    var description: String
    var topic: String
    /// A web Vault link (`https://…/#key`), a vault key, a read key or a read-only token.
    var link: String

    init(name: String, description: String = "", topic: String = "", link: String) {
        self.name = name
        self.description = description
        self.topic = topic
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        link = try c.decode(String.self, forKey: .link)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
    }
}

/// The gallery's list as a file, so that the list is data and not code. A vault that holds
/// `showcase.json` at its top adds its entries to the gallery of every device that has that vault.
///
///     {"v": 1, "entries": [{"name": "…", "description": "…", "topic": "…", "link": "…"}]}
///
/// A bare array of entries is read too.
enum Gallery {
    static let fileName = "showcase.json"

    struct File: Codable {
        var v: Int?
        var entries: [GalleryEntry]
    }

    /// The entries in a `showcase.json`, with empty links dropped and names filled in. Nothing for a
    /// file that is not one.
    static func entries(in data: Data) -> [GalleryEntry] {
        let decoder = JSONDecoder()
        let read = (try? decoder.decode(File.self, from: data))?.entries ?? (try? decoder.decode([GalleryEntry].self, from: data)) ?? []
        return read.compactMap { entry in
            var out = entry
            out.link = entry.link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !out.link.isEmpty else { return nil }
            if out.name.trimmingCharacters(in: .whitespaces).isEmpty { out.name = "A vault" }
            return out
        }
    }

    static func file(_ entries: [GalleryEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(File(v: 1, entries: entries))) ?? Data()
    }

    /// The address that opens an entry in the web Vault. A link is used as it is; a key is put after
    /// the `#` of the web Vault's address, where a browser keeps it and does not send it to the server.
    static func webAddress(of link: String) -> URL? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("https://") { return URL(string: text) }
        guard !text.isEmpty, !text.lowercased().hasPrefix("http") else { return nil }
        var key = text
        for prefix in ["sgit_private_vault_", "sgit_vk1_", "sgit_private_read_", "sgit_public_read_", "sgit_rk1_"] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
        }
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "#|")
        guard let fragment = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: AppInfo.webVault + "#" + fragment)
    }

    /// The key in an entry that this app can open itself, if it has one: a vault key or a read key.
    /// A read-only token (`ro-word-word-1234`) and a simple token open only in the web Vault.
    static func nativeKey(of link: String) -> String? {
        let text = VaultNaming.keyText(from: link)
        guard !text.lowercased().hasPrefix("http"), text.contains(":"), VaultKey.classify(text) != nil else { return nil }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        return VaultKey.isValidVaultId(String(text[text.index(after: colon)...])) ? text : nil
    }

    /// Entries by topic, topics in alphabetical order with the untitled ones last, filtered by a search.
    static func grouped(_ entries: [GalleryEntry], search: String = "") -> [(topic: String, entries: [GalleryEntry])] {
        let wanted = search.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var byTopic: [String: [GalleryEntry]] = [:]
        for entry in entries where seen.insert(entry.link).inserted {
            if !wanted.isEmpty,
               !"\(entry.name) \(entry.description) \(entry.topic)".lowercased().contains(wanted) { continue }
            byTopic[entry.topic.trimmingCharacters(in: .whitespaces), default: []].append(entry)
        }
        return byTopic.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        .map { topic in
            (topic, (byTopic[topic] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
