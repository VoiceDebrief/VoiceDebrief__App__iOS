import Foundation

/// Where a person's inbox is: an append lane on a vault of theirs. The append token can only write: anyone
/// holding it can drop a message in, nobody can read with it. What is dropped in is sealed to the card's
/// encryption key, so the inbox address needs no key of its own.
public struct InboxAddress: Codable, Equatable, Hashable, Sendable {
    /// The vault server, `https://…`, without a trailing slash.
    public var server: String
    public var vault: String
    /// The append token: it writes to the lane and does nothing else.
    public var append: String

    public static let defaultServer = "https://dev.send.sgraph.ai"

    public init(server: String = InboxAddress.defaultServer, vault: String, append: String) {
        var trimmed = server
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.server = trimmed
        self.vault = vault
        self.append = append
    }

    /// What is wrong with it. Empty when it can be written to.
    public var problems: [String] {
        var out: [String] = []
        if !(server.hasPrefix("https://") && URL(string: server)?.host != nil) { out.append("the server is not an https address") }
        if !(4...24).contains(vault.count) || !vault.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) {
            out.append("the vault id is not 4 to 24 lowercase letters and digits")
        }
        if !(16...128).contains(append.count) || !append.allSatisfy({ $0.isHexDigit }) { out.append("the append token is not hex") }
        return out
    }

    /// The lane's address for one operation: `write`, `list`, `fetch`, `mark-processed`, `configure`, `purge`.
    public func url(_ operation: String) -> URL? {
        URL(string: "\(server)/api/vault/append/\(operation)/\(vault)")
    }

    /// The `sgi1.` link VoiceDebrief's recipients and the conductor take: the same lane, with the card's
    /// encryption key. It has no server: `sgi1.` links always mean dev.send.sgraph.ai.
    public func laneLink(encryptPEM: String, name: String? = nil) throws -> String {
        let spki = try PKI.publicDER(encryptPEM)
        let tail = name.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) }.map { "#\($0)" } ?? ""
        return "sgi1.\(vault).\(append).\(PKI.base64url(spki))" + tail
    }

    var json: PKIJSON { .object(["server": .string(server), "vault": .string(vault), "append": .string(append)]) }

    init?(json: PKIJSON?) {
        guard let json, let server = json["server"]?.string, let vault = json["vault"]?.string,
              let append = json["append"]?.string else { return nil }
        self.init(server: server, vault: vault, append: append)
    }
}

/// A contact card: a person's name, their two public keys (the sgit key bundle), and their inbox, signed by
/// them. It is a statement in pki.sgit.ai's envelope, so pki.sgit.ai's `verifyStatement` checks it as it is:
///
///     { "v": 1, "type": "card", "registry": "sgit.ai/people",
///       "record": <signing fingerprint>, "signer": <the same>, "created_at": "2026-11-14T10:00:00Z",
///       "body": { "kind": "sgit.ai/people/card/v1", "name": "Ana",
///                 "bundle": <the public bundle, as `sgit pki export` prints it>,
///                 "inbox": { "server": "https://dev.send.sgraph.ai", "vault": "…", "append": "…" } },
///       "sig": <base64 of r‖s over the canonical bytes> }
///
/// `inbox` is absent on a newcomer's first card: they have no inbox until they hold an access key.
///
/// As text (for a QR code, a link, a WhatsApp message) the statement is rebuilt from what it cannot do
/// without, each part base64url:
///
///     sgc1.<encryption key SPKI>.<signing key SPKI>.<details>.<signature>
///
/// where details is the canonical JSON `{"created_at", "inbox"?, "label", "name"}`. The bundle is recomputed
/// from the two keys, so the text cannot claim a fingerprint its keys do not have. A 4096-bit card is about
/// 1,200 characters: a QR code of version 25 or so.
public struct ContactCard: Equatable, Hashable, Sendable {
    public static let registry = "sgit.ai/people"
    public static let type = "card"
    public static let kind = "sgit.ai/people/card/v1"
    public static let prefix = "sgc1."
    /// A page on the site that shows a card held in the address after `#`, which browsers never send to a server.
    public static let linkBase = "https://ios.app.voicedebrief.ai/card/"
    public static let maxNameLength = 80

    public var name: String
    public var bundle: PKIBundle
    public var inbox: InboxAddress?
    /// `2026-11-14T10:00:00Z`: seconds, UTC.
    public var createdAt: String
    /// Base64 of r‖s over the statement's canonical bytes.
    public var signature: String

    public var fingerprint: String { bundle.fingerprint }
    public var signingFingerprint: String { bundle.signingFingerprint }

    public enum Failure: Error, Equatable, LocalizedError {
        case noCard
        case malformed(String)
        case badKeys(String)
        case badSignature
        case badName

        public var errorDescription: String? {
            switch self {
            case .noCard: "There is no contact card in this."
            case .malformed(let why): "The card does not read (\(why))."
            case .badKeys(let why): "The card's keys are not sound: \(why)."
            case .badSignature: "The card's signature does not check: it was changed after it was signed."
            case .badName: "A name is 1 to \(ContactCard.maxNameLength) characters."
            }
        }
    }

    public init(name: String, bundle: PKIBundle, inbox: InboxAddress?, createdAt: String, signature: String) {
        self.name = name
        self.bundle = bundle
        self.inbox = inbox
        self.createdAt = createdAt
        self.signature = signature
    }

    // MARK: Making and checking

    public static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    public static func date(_ timestamp: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: timestamp)
    }

    public var created: Date? { Self.date(createdAt) }

    static func cleanName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNameLength, !trimmed.contains(where: \.isNewline) else { throw Failure.badName }
        return trimmed
    }

    /// The statement without `sig`.
    static func unsigned(name: String, bundle: PKIBundle, inbox: InboxAddress?, createdAt: String) -> PKIJSON {
        var body: [String: PKIJSON] = ["kind": .string(kind), "name": .string(name), "bundle": bundle.asJSON]
        if let inbox { body["inbox"] = inbox.json }
        return .object([
            "v": .int(1), "type": .string(type), "registry": .string(registry),
            "record": .string(bundle.signingFingerprint), "signer": .string(bundle.signingFingerprint),
            "created_at": .string(createdAt), "body": .object(body),
        ])
    }

    /// A card for `identity`, signed by it.
    public static func make(name: String, identity: PKIIdentity, inbox: InboxAddress?, at date: Date = Date()) throws -> ContactCard {
        let clean = try cleanName(name)
        let createdAt = timestamp(date)
        // The bundle as the card's text will rebuild it, so that the signature covers the same bytes either way.
        let bundle = PKI.bundle(encryptSPKI: try PKI.publicDER(identity.bundle.encrypt), signSPKI: try PKI.publicDER(identity.bundle.sign),
                                label: identity.bundle.label)
        let signed = try PKI.signStatement(unsigned(name: clean, bundle: bundle, inbox: inbox, createdAt: createdAt),
                                           signPKCS8: identity.signPKCS8)
        guard let sig = signed["sig"]?.string else { throw Failure.badSignature }
        return ContactCard(name: clean, bundle: bundle, inbox: inbox, createdAt: createdAt, signature: sig)
    }

    /// The statement as pki.sgit.ai would check it, `sig` included.
    public var statement: PKIJSON {
        var out = Self.unsigned(name: name, bundle: bundle, inbox: inbox, createdAt: createdAt)
        out["sig"] = .string(signature)
        return out
    }

    /// Throws unless the keys are sound (a test key under 4096 bits is allowed), the name is one, and the
    /// signature is the card's own signing key's over the rest.
    public func check() throws {
        if let first = PKI.problems(of: bundle).first(where: { !$0.contains("-bit") }) { throw Failure.badKeys(first) }
        guard (try? Self.cleanName(name)) == name else { throw Failure.badName }
        if let inbox, let first = inbox.problems.first { throw Failure.malformed("inbox: \(first)") }
        guard PKI.verifyStatement(statement, signPEM: bundle.sign) else { throw Failure.badSignature }
    }

    public var isSound: Bool { (try? check()) != nil }

    /// The same person's keys, compared by bytes: a later card from the same keys may change the name or the inbox.
    public func sameKeys(as other: ContactCard) -> Bool {
        bundle.fingerprint == other.bundle.fingerprint && bundle.signingFingerprint == other.bundle.signingFingerprint
            && (try? PKI.publicDER(bundle.encrypt)) == (try? PKI.publicDER(other.bundle.encrypt))
            && (try? PKI.publicDER(bundle.sign)) == (try? PKI.publicDER(other.bundle.sign))
    }

    // MARK: As text

    var details: PKIJSON {
        var fields: [String: PKIJSON] = ["name": .string(name), "label": .string(bundle.label), "created_at": .string(createdAt)]
        if let inbox { fields["inbox"] = inbox.json }
        return .object(fields)
    }

    /// `sgc1.…`, for a QR code or to paste anywhere.
    public func text() throws -> String {
        guard let signatureBytes = Data(base64Encoded: signature) else { throw Failure.malformed("signature") }
        return Self.prefix + [PKI.base64url(try PKI.publicDER(bundle.encrypt)), PKI.base64url(try PKI.publicDER(bundle.sign)),
                              PKI.base64url(details.data), PKI.base64url(signatureBytes)].joined(separator: ".")
    }

    /// A link that opens the card's page; the card itself stays in the browser.
    public func link() throws -> String { Self.linkBase + "#" + (try text()) }

    /// The first sound card in `text`, which may be a bare `sgc1.` code, a link, or a message with one inside.
    /// Every card found is checked; a card that does not check is not returned.
    public static func parse(_ text: String) throws -> ContactCard {
        var firstFailure: Failure?
        var search = text.startIndex
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        while let start = text.range(of: prefix, range: search..<text.endIndex) {
            search = start.upperBound
            var parts: [String] = [""]
            for c in text[start.upperBound...].utf8 {
                if c == 0x2E {
                    if parts.count == 4 { break }
                    parts.append("")
                } else if allowed.contains(c) {
                    parts[parts.count - 1].unicodeScalars.append(Unicode.Scalar(c))
                } else { break }
            }
            do {
                let card = try read(parts)
                try card.check()
                return card
            } catch let failure as Failure {
                if firstFailure == nil { firstFailure = failure }
            } catch {
                if firstFailure == nil { firstFailure = .malformed("\(error)") }
            }
        }
        throw firstFailure ?? Failure.noCard
    }

    static func read(_ parts: [String]) throws -> ContactCard {
        guard parts.count == 4 else { throw Failure.malformed("four parts") }
        guard (100...1200).contains(parts[0].utf8.count), (60...200).contains(parts[1].utf8.count),
              parts[2].utf8.count <= 3000, (80...90).contains(parts[3].utf8.count) else { throw Failure.malformed("lengths") }
        guard let encrypt = PKI.data(base64url: parts[0]), let sign = PKI.data(base64url: parts[1]),
              let detailBytes = PKI.data(base64url: parts[2]), let sig = PKI.data(base64url: parts[3]), sig.count == 64 else {
            throw Failure.malformed("base64url")
        }
        guard let details = try? PKIJSON(parsing: detailBytes), let name = details["name"]?.string,
              let createdAt = details["created_at"]?.string else { throw Failure.malformed("details") }
        let inbox: InboxAddress?
        if let value = details["inbox"] {
            guard let address = InboxAddress(json: value) else { throw Failure.malformed("inbox") }
            inbox = address
        } else {
            inbox = nil
        }
        let bundle = PKI.bundle(encryptSPKI: encrypt, signSPKI: sign, label: details["label"]?.string ?? "")
        return ContactCard(name: name, bundle: bundle, inbox: inbox, createdAt: createdAt, signature: sig.base64EncodedString())
    }

    /// A card as pki.sgit.ai's statement (the JSON a register or a file would hold), checked.
    public static func fromStatement(_ statement: PKIJSON) throws -> ContactCard {
        guard statement["v"] == .int(1), statement["type"] == .string(type), statement["registry"] == .string(registry),
              let body = statement["body"], body["kind"] == .string(kind), let name = body["name"]?.string,
              let bundleValue = body["bundle"], let createdAt = statement["created_at"]?.string,
              let sig = statement["sig"]?.string else { throw Failure.malformed("not a card statement") }
        guard let bundle = try? PKIBundle(json: bundleValue) else { throw Failure.badKeys("the bundle does not read") }
        guard statement["signer"] == .string(bundle.signingFingerprint), statement["record"] == .string(bundle.signingFingerprint) else {
            throw Failure.badSignature
        }
        let inbox: InboxAddress?
        if let value = body["inbox"] {
            guard let address = InboxAddress(json: value) else { throw Failure.malformed("inbox") }
            inbox = address
        } else {
            inbox = nil
        }
        let card = ContactCard(name: name, bundle: bundle, inbox: inbox, createdAt: createdAt, signature: sig)
        // The card rebuilds its statement from its fields: anything else in the statement is not covered.
        guard card.statement == statement else { throw Failure.malformed("fields a card does not have") }
        try card.check()
        return card
    }
}

/// Kept as its text, so that what is stored is exactly what was signed.
extension ContactCard: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = try ContactCard.parse(text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(try text())
    }
}
