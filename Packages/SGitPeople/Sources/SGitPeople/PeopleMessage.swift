import CryptoKit
import Foundation

/// What a message carries. pki.sgit.ai's messages have no type: one without is a text.
public enum MessageKind: String, Codable, CaseIterable, Sendable {
    case text
    /// A reference to a voice note kept in a vault: the audio itself is not in the message.
    case voiceNote = "voice-note"
    /// A secret for the recipient's store: an access key, a vault key, a password, a token, a note.
    case secret
    /// The key to a vault, to read it or to write to it.
    case vaultInvitation = "vault-invitation"
    /// The sender's card, in `card`: a first card, or a later one (a new inbox, a new name).
    case card
}

/// A secret as it travels. The value is in clear inside the message; the message is sealed to one person.
public struct SharedSecret: Codable, Equatable, Sendable {
    /// The sender's id for this secret, so that a later version replaces the one received before.
    public var id: String
    public var kind: SecretKind
    public var name: String
    public var value: String
    /// For an access key or a vault key: the server it is for.
    public var server: String?
    public var note: String?
    public var version: Int

    public init(id: String, kind: SecretKind, name: String, value: String, server: String? = nil, note: String? = nil, version: Int = 1) {
        self.id = id
        self.kind = kind
        self.name = name
        self.value = value
        self.server = server
        self.note = note
        self.version = version
    }
}

/// pki.sgit.ai's `grant`: an SG/Send access key handed over, as its own messages and `pki-agent.mjs` carry one.
public struct AccessGrant: Codable, Equatable, Sendable {
    public var service: String
    public var endpoint: String
    public var token: String
    public var name: String?

    public init(endpoint: String, token: String, name: String? = nil) {
        self.service = "sg-send"
        self.endpoint = endpoint
        self.token = token
        self.name = name
    }
}

/// A voice note, by where it is kept.
public struct VoiceNoteReference: Codable, Equatable, Sendable {
    public var vault: String
    public var path: String
    public var title: String
    public var seconds: Int?
    public var size: Int?
    public var sha256: String?

    public init(vault: String, path: String, title: String, seconds: Int? = nil, size: Int? = nil, sha256: String? = nil) {
        self.vault = vault
        self.path = path
        self.title = title
        self.seconds = seconds
        self.size = size
        self.sha256 = sha256
    }
}

/// An invitation to a vault: its key (a vault key writes, a read key only reads) and its server.
public struct VaultInvitation: Codable, Equatable, Sendable {
    public var name: String
    public var key: String
    public var server: String

    public init(name: String, key: String, server: String) {
        self.name = name
        self.key = key
        self.server = server
    }

    public var canWrite: Bool { key.hasPrefix("sgit_private_vault_") || key.hasPrefix("sgit_vk1_") }
}

/// One message between two people, in pki.sgit.ai's message form (`message.js`, `pki.sgit.ai/message/v1`), so that
/// pki.sgit.ai's pages and `pki-agent.mjs open` read what this writes and this reads what they write:
///
///     { "v": 1, "kind": "pki.sgit.ai/message/v1", "to": <recipient's signing fingerprint>,
///       "from": <sender's signing fingerprint>, "at": "2026-11-14T10:00:00Z", "expires"?: …, "text": "…",
///       "grant"?: { "service": "sg-send", "endpoint", "token", "name"? },
///       "sig": <sender's ECDSA over the canonical bytes without sig, plus a newline> }
///
/// This package adds fields of its own, inside the signature, which pki.sgit.ai's readers pass over: `type`, `id`,
/// `reply_to`, `card`, `secret`, `voice_note`, `vault`. `text` is always there, so that a reader that knows only
/// pki.sgit.ai's fields still shows something.
///
/// The message is then sealed in sgit's envelope to the recipient's encryption key, signed again over the
/// ciphertext. The inner signature covers `to`, so a signed message cannot be re-sealed to someone else and read
/// as addressed to them (which the envelope's signature alone does not prevent).
public struct PeopleMessage: Codable, Equatable, Identifiable, Sendable {
    public static let format = "pki.sgit.ai/message/v1"

    public var v: Int
    /// `pki.sgit.ai/message/v1` (the JSON field `kind`).
    public var format: String
    /// What it carries (the JSON field `type`); a message without one is a text.
    public var kind: MessageKind
    public var id: String
    /// The sender's signing fingerprint.
    public var from: String
    /// The recipient's signing fingerprint, as pki.sgit.ai addresses messages.
    public var to: String
    /// `2026-11-14T10:00:00Z` (the JSON field `at`).
    public var sentAt: String
    /// After this time the recipient should refuse it: an old code shown again reads as expired.
    public var expires: String?
    public var subject: String?
    public var text: String
    public var replyTo: String?
    /// The sender's card text (`sgc1.…`): on a `card` message, and on any message to someone who may not know them yet.
    public var card: String?
    public var secret: SharedSecret?
    public var grant: AccessGrant?
    public var voiceNote: VoiceNoteReference?
    public var vault: VaultInvitation?
    /// Base64 of r‖s over the canonical bytes without `sig`. Nil until signed.
    public var sig: String?

    enum CodingKeys: String, CodingKey {
        case v, id, from, to, expires, subject, text, card, secret, grant, vault, sig
        case format = "kind"
        case kind = "type"
        case sentAt = "at"
        case replyTo = "reply_to"
        case voiceNote = "voice_note"
    }

    public init(kind: MessageKind, from: String, to: String, sentAt: Date = Date(), id: String = PeopleMessage.newId(),
                replyTo: String? = nil, card: String? = nil, text: String? = nil, secret: SharedSecret? = nil,
                voiceNote: VoiceNoteReference? = nil, vault: VaultInvitation? = nil, expires: Date? = nil) {
        self.v = 1
        self.format = Self.format
        self.kind = kind
        self.id = id
        self.from = from
        self.to = to
        self.sentAt = ContactCard.timestamp(sentAt)
        self.expires = expires.map(ContactCard.timestamp)
        self.replyTo = replyTo
        self.card = card
        self.secret = secret
        self.voiceNote = voiceNote
        self.vault = vault
        if let secret, secret.kind == .accessKey {
            self.grant = AccessGrant(endpoint: secret.server ?? InboxAddress.defaultServer, token: secret.value, name: secret.name)
        }
        self.text = text ?? Self.summary(kind: kind, secret: secret, voiceNote: voiceNote, vault: vault)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        format = try c.decode(String.self, forKey: .format)
        kind = try c.decodeIfPresent(MessageKind.self, forKey: .kind) ?? .text
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decode(String.self, forKey: .to)
        sentAt = try c.decodeIfPresent(String.self, forKey: .sentAt) ?? ""
        expires = try c.decodeIfPresent(String.self, forKey: .expires)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        replyTo = try c.decodeIfPresent(String.self, forKey: .replyTo)
        card = try c.decodeIfPresent(String.self, forKey: .card)
        secret = try c.decodeIfPresent(SharedSecret.self, forKey: .secret)
        grant = try c.decodeIfPresent(AccessGrant.self, forKey: .grant)
        voiceNote = try c.decodeIfPresent(VoiceNoteReference.self, forKey: .voiceNote)
        vault = try c.decodeIfPresent(VaultInvitation.self, forKey: .vault)
        sig = try c.decodeIfPresent(String.self, forKey: .sig)
    }

    /// The words a reader that knows only pki.sgit.ai's fields shows.
    static func summary(kind: MessageKind, secret: SharedSecret?, voiceNote: VoiceNoteReference?, vault: VaultInvitation?) -> String {
        switch kind {
        case .text: ""
        case .secret: "A secret: \(secret?.name ?? "")"
        case .card: "A contact card"
        case .voiceNote: "A voice note: \(voiceNote?.title ?? "")"
        case .vaultInvitation: "A vault: \(vault?.name ?? "")"
        }
    }

    /// 16 random bytes as hex.
    public static func newId() -> String {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
    }

    public var sent: Date? { ContactCard.date(sentAt) }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let expires, let date = ContactCard.date(expires) else { return false }
        return date < now
    }

    /// What the kind needs is there.
    public var problems: [String] {
        var out: [String] = []
        if v != 1 || format != Self.format { out.append("not a v1 message") }
        switch kind {
        case .text: if text.isEmpty { out.append("a text message has no text") }
        case .voiceNote: if voiceNote == nil { out.append("a voice-note message has no reference") }
        case .secret: if secret == nil { out.append("a secret message has no secret") }
        case .vaultInvitation: if vault == nil { out.append("a vault invitation has no vault") }
        case .card: if card == nil { out.append("a card message has no card") }
        }
        return out
    }

    /// The fields as pki.sgit.ai's canonical JSON sees them.
    var statement: PKIJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Plain strings, integers and optionals: encoding cannot fail, and there is no non-integer number.
        guard let data = try? encoder.encode(self), let value = try? PKIJSON(parsing: data) else { return .object([:]) }
        return value
    }

    /// The bytes that are sealed: the signed message, canonical.
    func signedJSON(by sender: PKIIdentity) throws -> Data {
        try PKI.signStatement(statement, signPKCS8: sender.signPKCS8).data
    }

    /// For tests and plumbing: the message JSON as it stands, signed or not.
    public var json: Data { statement.data }

    // MARK: Sealing

    /// The envelope text (`PKI.seal`): base64 of sgit's v2 envelope JSON, signed inside and out.
    public func seal(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        guard from == sender.bundle.signingFingerprint else { throw PKIError.format("the message's from is not the sender's key") }
        guard to == recipient.signingFingerprint else { throw PKIError.format("the message's to is not the recipient's key") }
        return try PKI.seal(try signedJSON(by: sender), to: recipient, signedBy: sender)
    }

    /// What goes in an append lane's `payload`: the envelope text, base64 once more, as every lane holds it.
    public func lanePayload(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        LaneCrypto.lanePayload(encText: try seal(to: recipient, from: sender))
    }

    /// The same sealed message as pki.sgit.ai's `m1.` code, to hand over without an inbox (a QR code, a link, WhatsApp).
    public func sealedText(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        try SealedText.code(envelope: try seal(to: recipient, from: sender), to: recipient.signingFingerprint)
    }
}

/// How far a received message's sender is known.
public enum SenderTrust: String, Codable, Equatable, Sendable {
    /// Signed by a contact's key, and the signatures check.
    case contact
    /// Signed by the key of the card the message carries, which checks; the sender is not yet a contact.
    case cardInside = "card-inside"
    /// Signed by a key this device does not know, and no card came with it: unchecked, not forged.
    case unknown
    /// A signature, or the `from` and `to` inside, do not match: never shown as from anyone.
    case forged
    /// Not signed at all.
    case unsigned
}

/// A message opened on this device.
public struct OpenedMessage: Equatable, Sendable {
    public var message: PeopleMessage
    public var trust: SenderTrust
    /// The signing fingerprint the message names as its sender.
    public var signer: String?
    /// The card the message carries, checked, when it has one.
    public var card: ContactCard?
    public var expired: Bool

    public init(message: PeopleMessage, trust: SenderTrust, signer: String?, card: ContactCard?, expired: Bool = false) {
        self.message = message
        self.trust = trust
        self.signer = signer
        self.card = card
        self.expired = expired
    }
}

extension PeopleMessage {
    public enum OpenFailure: Error, Equatable, LocalizedError {
        case notForMe
        case notAMessage(String)

        public var errorDescription: String? {
            switch self {
            case .notForMe: "This was not sealed to your key, or it was changed on the way."
            case .notAMessage(let why): "It opened, but it is not a message (\(why))."
            }
        }
    }

    /// Opens an envelope text with `me`; checks the message's own signature and the envelope's against a contact's
    /// key or, failing that, the card inside; and checks that `to` is this key and `from` the key that signed.
    public static func open(envelope encText: String, me: PKIIdentity, contacts: [PKIBundle], now: Date = Date()) throws -> OpenedMessage {
        let opened: PKIOpened
        do { opened = try PKI.unseal(encText, encryptPKCS8: me.encryptPKCS8, signers: contacts) } catch { throw OpenFailure.notForMe }
        guard let value = try? PKIJSON(parsing: opened.bytes),
              let message = try? JSONDecoder().decode(PeopleMessage.self, from: opened.bytes),
              message.format == Self.format else {
            throw OpenFailure.notAMessage("not a pki.sgit.ai message")
        }
        if let first = message.problems.first { throw OpenFailure.notAMessage(first) }
        let card = message.card.flatMap { try? ContactCard.parse($0) }
        let expired = message.isExpired(at: now)
        guard message.sig != nil, !message.from.isEmpty else {
            return OpenedMessage(message: message, trust: .unsigned, signer: opened.signer, card: card, expired: expired)
        }
        let trust: SenderTrust
        func checks(_ bundle: PKIBundle) -> Bool {
            // The message's own signature, and the envelope's when it has one (it must be the same key's).
            guard PKI.verifyStatement(value, signPEM: bundle.sign) else { return false }
            if opened.signed {
                guard opened.signer == bundle.signingFingerprint else { return false }
                let outer = try? PKI.unseal(encText, encryptPKCS8: me.encryptPKCS8, signers: [bundle])
                return outer?.verified == true
            }
            return true
        }
        if let contact = contacts.first(where: { $0.signingFingerprint == message.from }) {
            trust = checks(contact) ? .contact : .forged
        } else if let card, card.signingFingerprint == message.from {
            trust = checks(card.bundle) ? .cardInside : .forged
        } else {
            trust = .unknown
        }
        let addressed = message.to == me.bundle.signingFingerprint && (opened.signer == nil || opened.signer == message.from)
        return OpenedMessage(message: message, trust: addressed ? trust : .forged, signer: message.from, card: card, expired: expired)
    }

    /// Opens what an append lane stored (`content`): base64 of the envelope text.
    public static func open(laneContent: String, me: PKIIdentity, contacts: [PKIBundle], now: Date = Date()) throws -> OpenedMessage {
        let encText: String
        do { encText = try LaneCrypto.encText(fromLaneContent: laneContent) } catch { throw OpenFailure.notForMe }
        return try open(envelope: encText, me: me, contacts: contacts, now: now)
    }
}

/// A sealed message handed over as text, pki.sgit.ai's `m1.` code (`message.js`): the envelope's binary fields as
/// base64url rather than base64 inside JSON inside base64, so a short message fits one QR code.
///
///     m1.<recipient's signing fingerprint, 16 hex>.<w>.<i>.<c>[.<s>.<sender's signing fingerprint, 16 hex>]
///
/// As a link, `https://pki.sgit.ai/m/#m1.…`: pki.sgit.ai's page opens it in the reader's browser. Its QR form for an
/// agent is the strict JSON `{"v":1,"kind":"pki.sgit.ai/qr/sealed/v1","to","from","code"}`, which is read too.
public enum SealedText {
    public static let prefix = "m1."
    public static let linkBase = "https://pki.sgit.ai/m/#"
    /// pki.sgit.ai's own limit for one QR code (version 40 at level L holds 2,953 bytes; room is left for the address).
    public static let maxQRCharacters = 2300

    static func short(_ fingerprint: String) -> String { String(fingerprint.dropFirst("sha256:".count)) }

    /// The `m1.` code for an envelope text sealed to `to` (a signing fingerprint).
    public static func code(envelope encText: String, to: String) throws -> String {
        guard let json = Data(base64Encoded: encText), let env = try? JSONDecoder().decode(LaneCrypto.Envelope.self, from: json),
              let w = Data(base64Encoded: env.w), let i = Data(base64Encoded: env.i), let c = Data(base64Encoded: env.c) else {
            throw PKIError.format("not an sgit envelope")
        }
        var parts = ["m1", short(to), PKI.base64url(w), PKI.base64url(i), PKI.base64url(c)]
        if let s = env.s, let f = env.f, let sig = Data(base64Encoded: s) { parts += [PKI.base64url(sig), short(f)] }
        return parts.joined(separator: ".")
    }

    public static func link(_ code: String) -> String { linkBase + code }

    /// The envelope text in `text`: a bare code, a link, a message with one inside, or the QR JSON object.
    /// The envelope is rebuilt as pki.sgit.ai rebuilds it.
    public static func envelope(in text: String) -> String? {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        let hex = Set("0123456789abcdef".utf8)
        var search = text.startIndex
        while let start = text.range(of: prefix, range: search..<text.endIndex) {
            search = start.upperBound
            // Not the tail of some other code: what comes before must not be part of a base64url run.
            if start.lowerBound > text.startIndex, let before = text[text.index(before: start.lowerBound)].asciiValue,
               allowed.contains(before) || before == UInt8(ascii: ".") { continue }
            var parts: [String] = [""]
            for c in text[start.upperBound...].utf8 {
                if c == 0x2E {
                    if parts.count == 6 { break }
                    parts.append("")
                } else if allowed.contains(c) {
                    parts[parts.count - 1].unicodeScalars.append(Unicode.Scalar(c))
                } else { break }
            }
            guard parts.count == 4 || parts.count == 6, parts[0].utf8.count == 16, parts[0].utf8.allSatisfy(hex.contains),
                  let w = PKI.data(base64url: parts[1]), let i = PKI.data(base64url: parts[2]), let c = PKI.data(base64url: parts[3]) else { continue }
            var json = "{\"v\": 2, \"w\": \"\(w.base64EncodedString())\", \"i\": \"\(i.base64EncodedString())\", \"c\": \"\(c.base64EncodedString())\""
            if parts.count == 6 {
                guard (80...90).contains(parts[4].utf8.count), let s = PKI.data(base64url: parts[4]), parts[5].utf8.count == 16,
                      parts[5].utf8.allSatisfy(hex.contains) else { continue }
                json += ", \"s\": \"\(s.base64EncodedString())\", \"f\": \"sha256:\(parts[5])\""
            }
            return Data((json + "}").utf8).base64EncodedString()
        }
        return nil
    }
}
