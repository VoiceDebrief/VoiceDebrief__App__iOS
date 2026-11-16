import Foundation

/// Reads vCard 2.1, 3.0 and 4.0 files (`.vcf`), one or many cards, as Contacts and most phones export them.
enum VCardReader {
    static func read(_ text: String, file: String, at: Date) -> [ContactCandidate] {
        var cards: [ContactCandidate] = []
        var current: ContactCandidate?
        var structuredName: String?
        var index = 0

        for line in unfold(text) {
            guard let colon = firstUnquotedColon(line) else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            var parts = head.split(separator: ";").map(String.init)
            // "item1.EMAIL" (Apple's grouping) is still an EMAIL.
            var property = parts.removeFirst().uppercased()
            if let dot = property.lastIndex(of: ".") { property = String(property[property.index(after: dot)...]) }

            switch property {
            case "BEGIN" where value.uppercased() == "VCARD":
                index += 1
                structuredName = nil
                current = ContactCandidate(name: "", source: Source(saidBy: "A vCard file", at: at, from: "\(file), card \(index)"))
            case "END" where value.uppercased() == "VCARD":
                if var card = current {
                    if card.name.isEmpty, let structuredName { card.name = structuredName }
                    card.settleName()
                    if card.isUsable { cards.append(card) }
                }
                current = nil
            case "FN":
                current?.name = unescape(value)
            case "N":
                // Family;Given;Additional;Prefix;Suffix
                let n = splitUnescaped(value)
                let given = n.count > 1 ? n[1] : ""
                let family = n.first ?? ""
                structuredName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            case "EMAIL":
                let v = unescape(value).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { current?.emails.append(v) }
            case "TEL":
                let v = unescape(value).replacingOccurrences(of: "tel:", with: "").trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { current?.phones.append(v) }
            case "ORG":
                let org = splitUnescaped(value).filter { !$0.isEmpty }.joined(separator: ", ")
                if !org.isEmpty { current?.organisation = org }
            case "TITLE", "ROLE":
                let v = unescape(value)
                if !v.isEmpty, current?.role == nil { current?.role = v }
            case "URL", "X-SOCIALPROFILE":
                let v = unescape(value)
                if !v.isEmpty { current?.links.append(v) }
            case "NOTE":
                let v = unescape(value)
                if !v.isEmpty { current?.notes.append(v) }
            default:
                break
            }
        }
        return cards
    }

    /// RFC 6350 line folding: a line starting with a space or a tab continues the one before.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines.filter { !$0.isEmpty }
    }

    private static func firstUnquotedColon(_ line: String) -> String.Index? {
        var quoted = false
        for i in line.indices {
            if line[i] == "\"" { quoted.toggle() }
            if line[i] == ":" && !quoted { return i }
        }
        return nil
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Splits on `;` that is not escaped, then unescapes each part.
    static func splitUnescaped(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaping = false
        for c in s {
            if escaping { current.append("\\"); current.append(c); escaping = false }
            else if c == "\\" { escaping = true }
            else if c == ";" { parts.append(unescape(current)); current = "" }
            else { current.append(c) }
        }
        parts.append(unescape(current))
        return parts
    }
}
