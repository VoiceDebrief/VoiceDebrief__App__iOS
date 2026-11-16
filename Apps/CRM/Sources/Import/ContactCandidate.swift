import Foundation

/// Something found in a file that looks like a contact, before it is a proposal: the plain values,
/// and where they came from. Readers make these; `ProposalMaker` turns them into proposals.
struct ContactCandidate: Hashable, Sendable {
    var name: String
    var emails: [String] = []
    var phones: [String] = []
    var organisation: String?
    var role: String?
    var links: [String] = []
    var notes: [String] = []
    /// Where it came from: the file and the place in it.
    var source: Source

    /// A candidate with neither a name nor a way to reach them is not a contact.
    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || !emails.isEmpty || !phones.isEmpty
    }

    /// Fills a missing name from the email's local part, so a list of addresses still makes people.
    mutating func settleName() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty, let email = emails.first, let local = email.split(separator: "@").first {
            name = local.split(whereSeparator: { ".-_".contains($0) })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

/// Small normalisations used to match people across sources.
enum ContactKeys {
    static func email(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "mailto:", with: "")
    }

    /// Digits only, with a leading plus kept; the last nine digits compare numbers written with and
    /// without a country code.
    static func phone(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        return String(digits.suffix(9))
    }

    static func name(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter })
            .joined(separator: " ")
    }

    static func isEmail(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@"), t.filter({ $0 == "@" }).count == 1 else { return false }
        let domain = t[t.index(after: at)...]
        return at > t.startIndex && domain.contains(".") && !t.contains(" ")
    }
}
