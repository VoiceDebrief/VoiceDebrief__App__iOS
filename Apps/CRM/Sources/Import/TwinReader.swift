import Foundation

/// Reads the email cell's mailbox twin (twin v1, agreed 16 November 2026: AgentiCCells__Cell__Email,
/// docs/plan/twin.md): `mailbox.json`, `threads/<t>.json`, `raw/messages/…` or `clean/messages/…`,
/// `index/correspondents.json`. Each correspondent becomes a candidate with their name, their email
/// threads as interactions, and a follow-up when they wrote last and nobody answered. As the email cell's
/// policy says, only verified correspondence counts: someone whose mail passed DMARC, or someone you wrote
/// to. Others are listed and left out. Read with the person's own key; nothing is written to the twin.
enum TwinReader {
    struct Result {
        var candidates: [ContactCandidate] = []
        var skipped: [ImportScanner.Skipped] = []
        var taken: Set<String> = []
        var mailbox: String?
    }

    struct Message {
        var id: String
        var fromAddress: String
        var fromName: String?
        var to: [(address: String, name: String?)]
        var date: Date
        var inbound: Bool
        var subject: String
    }

    static let folders = ["raw", "clean", "threads", "attachments", "index"]

    static func isTwin(_ files: [(path: String, data: Data)]) -> Bool {
        files.contains { $0.path == "mailbox.json" && schema(of: $0.data)?.hasPrefix("twin.mailbox/") == true }
    }

    private static func schema(of data: Data) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (o["schema"] as? String) ?? (o["format"] as? String)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func address(_ any: Any?) -> (address: String, name: String?)? {
        guard let o = any as? [String: Any], let a = o["address"] as? String else { return nil }
        let name = (o["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return (ContactKeys.email(a), name)
    }

    static func read(_ files: [(path: String, data: Data)], file prefix: String, at: Date) -> Result {
        var result = Result()
        guard isTwin(files) else { return result }
        for (path, _) in files {
            let first = path.split(separator: "/").first.map(String.init) ?? ""
            if folders.contains(first) || ["mailbox.json", "labels.json"].contains(path) { result.taken.insert(path) }
        }
        let me = files.first { $0.path == "mailbox.json" }.flatMap { object($0.data) }.flatMap { $0["address"] as? String }.map(ContactKeys.email)
        result.mailbox = me

        // Messages, the person's raw copy first, the filtered copy where there is no raw one.
        var messages: [String: Message] = [:]
        for prefixFolder in ["clean/messages/", "raw/messages/"] {
            for (path, data) in files where path.hasPrefix(prefixFolder) && path.hasSuffix(".json") {
                guard let o = object(data), let id = o["id"] as? String, let from = address(o["from"]),
                      let dateText = o["date"] as? String, let date = TeamCRMReader.date(dateText) else { continue }
                let to = ((o["to"] as? [Any]) ?? []).compactMap(address) + ((o["cc"] as? [Any]) ?? []).compactMap(address)
                let inbound = (o["direction"] as? String).map { $0 == "inbound" } ?? (from.address != me)
                messages[id] = Message(id: id, fromAddress: from.address, fromName: from.name, to: to, date: date,
                                       inbound: inbound, subject: (o["subject"] as? String) ?? "")
            }
        }

        struct Thread { var id: String; var subject: String; var messages: [String]; var participants: [String]; var last: Date }
        var threads: [Thread] = []
        for (path, data) in files where path.hasPrefix("threads/") && path.hasSuffix(".json") {
            guard let o = object(data), let id = o["id"] as? String else { continue }
            let ids = (o["messages"] as? [String]) ?? []
            let parts = ((o["participants"] as? [String]) ?? []).map(ContactKeys.email)
            let last = (o["last_date"] as? String).flatMap(TeamCRMReader.date) ?? ids.compactMap { messages[$0]?.date }.max() ?? at
            threads.append(Thread(id: id, subject: (o["subject"] as? String) ?? "(no subject)", messages: ids, participants: parts, last: last))
        }

        // Correspondents: {"schema": "twin.correspondents/1", "mailbox": …, "correspondents": {address: counts}}, as the
        // real sync writes it; a bare map or a list of entries is also read. Your own address is always left out
        // by mailbox.json's "address", never by trusting a thread's participants.
        var counts: [String: [String: Any]] = [:]
        if let index = files.first(where: { $0.path == "index/correspondents.json" }), let root = object(index.data) {
            let body = (root["correspondents"] as? [String: Any]) ?? root
            for (key, value) in body {
                if let entry = value as? [String: Any], key.contains("@") { counts[ContactKeys.email(key)] = entry }
            }
            if let list = root["correspondents"] as? [[String: Any]] {
                for entry in list { if let a = entry["address"] as? String { counts[ContactKeys.email(a)] = entry } }
            }
        }

        let source = { (date: Date) in
            Source(saidBy: "Your mailbox (the email twin)", at: date.toTheSecond, from: "\(prefix)/index/correspondents.json")
        }
        for (addr, entry) in counts.sorted(by: { $0.key < $1.key }) where addr != me {
            let verified = (entry["inbound_verified"] as? Int ?? 0) > 0
            let wroteTo = (entry["outbound"] as? Int ?? 0) > 0
            guard verified || wroteTo else {
                result.skipped.append(.init(path: "\(addr)", reason: "wrote to you, but no message passed DMARC and you never wrote back: not counted as correspondence"))
                continue
            }
            let name = messages.values.first { $0.fromAddress == addr && $0.fromName != nil }?.fromName
                ?? messages.values.flatMap(\.to).first { $0.address == addr && $0.name != nil }?.name ?? ""
            let mine = threads.filter { $0.participants.contains(addr) }.sorted { $0.last < $1.last }
            var c = ContactCandidate(name: name, emails: [addr], source: source(mine.last?.last ?? at))
            c.events = mine.map { CandidateEvent(at: $0.last, channel: .email, summary: "Email: \($0.subject) (\($0.messages.count) \($0.messages.count == 1 ? "message" : "messages"))") }
            // They wrote last and nobody answered: a reply is owed.
            if let owed = mine.last(where: { t in
                guard let lastID = t.messages.last, let m = messages[lastID] else { return false }
                return m.inbound && m.fromAddress == addr
            }) {
                c.nextStep = "Reply: \(owed.subject)"
                c.due = Calendar(identifier: .gregorian).date(byAdding: .day, value: 2, to: owed.last)
                c.stage = "in conversation"
            }
            c.notes = ["In your mailbox: \(entry["inbound"] as? Int ?? 0) received, \(entry["outbound"] as? Int ?? 0) sent"]
            c.settleName()
            result.candidates.append(c)
        }
        return result
    }
}
