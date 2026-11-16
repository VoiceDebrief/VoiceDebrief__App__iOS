import Foundation

/// Turns the lines of text read from a photo of a business card or a badge (by Vision, on the device)
/// into a candidate. Plain rules, no model: an email, a phone, a link, then the name, role and
/// organisation from what is left. Every value it finds is marked as read from the photo, so the
/// review screen can show it as a guess.
enum CardTextReader {
    static let roleWords = ["ceo", "cto", "cfo", "coo", "founder", "co-founder", "director", "head", "manager", "engineer",
                            "partner", "president", "lead", "officer", "investor", "developer", "designer", "vp", "chief",
                            "principal", "analyst", "consultant", "advisor", "adviser", "associate", "product", "sales", "marketing"]
    static let organisationWords = ["ltd", "limited", "inc", "llc", "gmbh", "plc", "lda", "s.a.", "sa", "bv", "ag",
                                    "labs", "ventures", "capital", "group", "technologies", "university", "foundation"]

    static func read(lines raw: [String], file: String, at: Date) -> ContactCandidate? {
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var c = ContactCandidate(name: "", source: Source(saidBy: "Text read from a photo on this device", at: at, from: file))
        var rest: [String] = []

        for line in lines {
            let words = line.split(separator: " ").map(String.init)
            if let email = words.first(where: ContactKeys.isEmail) {
                c.emails.append(email.trimmingCharacters(in: CharacterSet(charactersIn: ",;()<>")))
            } else if looksLikePhone(line) {
                c.phones.append(line.replacingOccurrences(of: phoneLabel, with: "", options: [.regularExpression, .caseInsensitive]))
            } else if looksLikeLink(line) {
                c.links.append(line)
            } else {
                rest.append(line)
            }
        }

        var remaining: [String] = []
        for line in rest {
            let lower = line.lowercased()
            let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "." }).map(String.init))
            if c.role == nil, !words.isDisjoint(with: roleWords) {
                c.role = line
            } else if c.organisation == nil, !words.isDisjoint(with: organisationWords) {
                c.organisation = line
            } else {
                remaining.append(line)
            }
        }
        if let name = remaining.first(where: looksLikeName) {
            c.name = name
            remaining.removeAll { $0 == name }
        }
        if c.organisation == nil, let org = remaining.first { c.organisation = org; remaining.removeFirst() }
        c.notes = remaining.isEmpty ? [] : ["Also on the card: " + remaining.joined(separator: " / ")]
        c.settleName()
        return c.isUsable ? c : nil
    }

    static let phoneLabel = "^(tel|phone|mobile|mob|cell|m|t|p)[:.]?\\s*"

    static func looksLikePhone(_ line: String) -> Bool {
        let bare = line.replacingOccurrences(of: phoneLabel, with: "", options: [.regularExpression, .caseInsensitive])
        return bare.filter(\.isNumber).count >= 7 && bare.allSatisfy { $0.isNumber || " +-().".contains($0) }
    }

    static func looksLikeLink(_ line: String) -> Bool {
        let l = line.lowercased()
        return !l.contains(" ") && (l.hasPrefix("http") || l.hasPrefix("www.") || l.contains("linkedin.com") || l.range(of: "^[a-z0-9-]+\\.[a-z]{2,}(/.*)?$", options: .regularExpression) != nil)
    }

    /// Two to four words, letters (with hyphens and apostrophes), each starting with a capital.
    static func looksLikeName(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard (2...4).contains(words.count) else { return false }
        return words.allSatisfy { w in
            guard let f = w.first, f.isUppercase else { return false }
            return w.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "." }
        }
    }
}
