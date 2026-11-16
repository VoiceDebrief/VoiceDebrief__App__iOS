import Foundation

/// Reads contacts from a CSV file (as spreadsheets, LinkedIn and event apps export them) or from a
/// JSON list of objects. Columns are recognised by their names, in English and loosely.
enum TableReader {
    enum Field: Hashable {
        case name, first, last, email, phone, organisation, role, link, note
        /// A column kept as a labelled note: "Industry: Fintech".
        case extra(String)
    }

    /// Which field a column heading means, or nil.
    static func field(for heading: String) -> Field? {
        let h = heading.lowercased().filter { $0.isLetter }
        switch h {
        case "name", "fullname", "displayname", "contact", "contactname", "person": return .name
        case "firstname", "givenname", "first", "forename": return .first
        case "lastname", "surname", "familyname", "last": return .last
        case "email", "emailaddress", "mail", "workemail", "emailaddresses": return .email
        case "phone", "phonenumber", "mobile", "mobilephone", "tel", "telephone", "cell", "whatsapp": return .phone
        case "company", "organisation", "organization", "org", "employer", "companyname", "startup": return .organisation
        case "title", "jobtitle", "role", "position", "job": return .role
        case "linkedin", "linkedinurl", "url", "website", "web", "profile", "profileurl", "twitter", "x": return .link
        case "notes", "note", "comment", "comments", "remarks", "context", "met", "metat": return .note
        case "industry", "sector": return .extra("Industry")
        case "location", "locationcountry", "country", "city": return .extra("Location")
        case "connectedat", "connectedon", "connected", "date": return .extra("Connected")
        case "requestmessage", "message": return .extra("Their message")
        default: return nil
        }
    }

    // MARK: CSV

    static func readCSV(_ text: String, file: String, at: Date) -> [ContactCandidate] {
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let fields = header.map(field(for:))
        guard fields.contains(where: { $0 == .name || $0 == .first || $0 == .email || $0 == .phone }) else { return [] }
        var out: [ContactCandidate] = []
        for (n, row) in rows.dropFirst().enumerated() {
            var values: [(Field, String)] = []
            for (i, cell) in row.enumerated() where i < fields.count {
                if let f = fields[i] { values.append((f, cell)) }
            }
            if var c = candidate(values, source: Source(saidBy: "A CSV file", at: at, from: "\(file), row \(n + 2)")) {
                c.settleName()
                if c.isUsable { out.append(c) }
            }
        }
        return out
    }

    /// RFC 4180: quoted fields may hold commas, quotes (doubled) and line breaks. A semicolon is taken
    /// as the separator when the first line has more of them than commas (European spreadsheets).
    static func parseCSV(_ text: String) -> [[String]] {
        let firstLine = text.prefix { !$0.isNewline }
        let separator: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" && cell.isEmpty {
                quoted = true
            } else if c == separator {
                row.append(cell); cell = ""
            } else if c.isNewline {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(cell); cell = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                cell.append(c)
            }
            i += 1
        }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: JSON

    /// A list of objects, or an object holding one under a key such as `contacts` or `people`.
    static func readJSON(_ data: Data, file: String, at: Date) -> [ContactCandidate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var list: [[String: Any]] = []
        if let array = root as? [[String: Any]] {
            list = array
        } else if let object = root as? [String: Any] {
            for key in ["contacts", "people", "attendees", "leads", "connections", "items", "data"] {
                if let array = object[key] as? [[String: Any]] { list = array; break }
            }
        }
        var out: [ContactCandidate] = []
        for (n, object) in list.enumerated() {
            var values: [(Field, String)] = []
            for (key, value) in object {
                guard let f = field(for: key) else { continue }
                if let s = value as? String { values.append((f, s)) }
                else if let strings = value as? [String] { values += strings.map { (f, $0) } }
                else if let number = value as? NSNumber { values.append((f, number.stringValue)) }
            }
            if var c = candidate(values, source: Source(saidBy: "A JSON list", at: at, from: "\(file), item \(n + 1)")) {
                c.settleName()
                if c.isUsable { out.append(c) }
            }
        }
        return out
    }

    private static func candidate(_ values: [(Field, String)], source: Source) -> ContactCandidate? {
        var c = ContactCandidate(name: "", source: source)
        var first = "", last = ""
        for (f, raw) in values {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { continue }
            switch f {
            case .name: c.name = v
            case .first: first = v
            case .last: last = v
            case .email: c.emails += v.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == " " }).map(String.init).filter(ContactKeys.isEmail)
            case .phone: c.phones.append(v)
            case .organisation: c.organisation = v
            case .role: c.role = v
            case .link: c.links.append(v)
            case .note: c.notes.append(v)
            case .extra(let label): c.notes.append("\(label): \(v)")
            }
        }
        if c.name.isEmpty { c.name = [first, last].filter { !$0.isEmpty }.joined(separator: " ") }
        return c
    }
}
