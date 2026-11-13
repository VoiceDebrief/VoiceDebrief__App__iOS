import Foundation

/// Somebody a note can be sent to: a person, another device, an agent session. A recipient is a
/// name and a lane link. The link holds where the lane is, a token that can only write, and the
/// recipient's public key: safe to pass around, useless for reading.
struct Recipient: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var link: String

    var id: String { link }
    var lane: DeveloperLane? { DeveloperLane.parse(link) }
}

enum RecipientLink {
    /// The lane link in a piece of text (typed, pasted or read from a QR code), and the name that
    /// follows it after a `#`, if there is one: `sgi1.<vault>.<token>.<key>#Maria%20Silva`.
    /// Nil when there is no usable link.
    static func read(_ text: String) -> (link: String, name: String)? {
        guard let match = text.firstMatch(of: #/sgi1\.[a-z0-9]{4,24}\.[0-9a-f]{16,128}\.[A-Za-z0-9_-]{200,3000}/#) else { return nil }
        let link = String(match.0)
        guard DeveloperLane.parse(link) != nil else { return nil }
        var name = ""
        let rest = text[match.range.upperBound...]
        if rest.hasPrefix("#") {
            let raw = rest.dropFirst().prefix { !$0.isWhitespace }
            name = (raw.removingPercentEncoding ?? String(raw)).trimmingCharacters(in: .whitespaces)
        }
        return (link, String(name.prefix(60)))
    }

    /// The text a QR code carries for a recipient: the link, then `#` and the name.
    static func write(_ recipient: Recipient) -> String {
        let name = recipient.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return name.isEmpty ? recipient.link : recipient.link + "#" + name
    }

    /// Adds a recipient, or renames the one that already has this link.
    static func adding(name: String, link: String, to list: [Recipient]) -> [Recipient] {
        guard let lane = DeveloperLane.parse(link) else { return list }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = Recipient(name: trimmed.isEmpty ? "Lane \(lane.vault)" : trimmed, link: link)
        var list = list
        if let index = list.firstIndex(where: { $0.link == link }) {
            list[index] = recipient
        } else {
            list.append(recipient)
        }
        return list
    }
}
