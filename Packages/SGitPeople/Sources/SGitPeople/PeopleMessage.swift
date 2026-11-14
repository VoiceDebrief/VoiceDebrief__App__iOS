import CryptoKit
import Foundation

/// What a message carries.
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

/// One message between two people. Before sealing it is JSON (sorted keys); it is then sealed to the
/// recipient's encryption key and signed with the sender's signing key, in sgit's envelope (`PKI.seal`), so
/// the server holds bytes it cannot read and the recipient can tell who sent it.
///
///     { "v": 1, "format": "sgit.ai/people/message/v1", "id": <random>, "kind": "text",
///       "from": <sender's signing fingerprint>, "to": <recipient's encryption fingerprint>,
///       "sent_at": "2026-11-14T10:00:00Z", "text": "…" }
///
/// `from` and `to` are inside the seal and are checked on opening: `from` must be the key that signed the
/// envelope, and `to` the key that opened it, so a signed message cannot be passed on to someone else as
/// if it had been written to them.
public struct PeopleMessage: Codable, Equatable, Identifiable, Sendable {
    public static let format = "sgit.ai/people/message/v1"

    public var v: Int
    public var format: String
    public var id: String
    public var kind: MessageKind
    public var from: String
    public var to: String
    public var sentAt: String
    public var replyTo: String?
    /// The sender's card text (`sgc1.…`): on a `card` message, and on any message to someone who may not know them yet.
    public var card: String?
    public var text: String?
    public var secret: SharedSecret?
    public var voiceNote: VoiceNoteReference?
    public var vault: VaultInvitation?

    enum CodingKeys: String, CodingKey {
        case v, format, id, kind, from, to, card, text, secret, vault
        case sentAt = "sent_at"
        case replyTo = "reply_to"
        case voiceNote = "voice_note"
    }

    public init(kind: MessageKind, from: String, to: String, sentAt: Date = Date(), id: String = PeopleMessage.newId(),
                replyTo: String? = nil, card: String? = nil, text: String? = nil, secret: SharedSecret? = nil,
                voiceNote: VoiceNoteReference? = nil, vault: VaultInvitation? = nil) {
        self.v = 1
        self.format = Self.format
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
        self.sentAt = ContactCard.timestamp(sentAt)
        self.replyTo = replyTo
        self.card = card
        self.text = text
        self.secret = secret
        self.voiceNote = voiceNote
        self.vault = vault
    }

    /// 16 random bytes as hex.
    public static func newId() -> String {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
    }

    public var sent: Date? { ContactCard.date(sentAt) }

    /// What the kind needs is there.
    public var problems: [String] {
        var out: [String] = []
        if v != 1 || format != Self.format { out.append("not a v1 message") }
        switch kind {
        case .text: if text == nil { out.append("a text message has no text") }
        case .voiceNote: if voiceNote == nil { out.append("a voice-note message has no reference") }
        case .secret: if secret == nil { out.append("a secret message has no secret") }
        case .vaultInvitation: if vault == nil { out.append("a vault invitation has no vault") }
        case .card: if card == nil { out.append("a card message has no card") }
        }
        return out
    }

    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding plain strings, numbers and optionals cannot fail.
        return (try? encoder.encode(self)) ?? Data()
    }

    // MARK: Sealing

    /// The envelope text (`PKI.seal`): base64 of sgit's v2 envelope JSON, signed.
    public func seal(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        guard from == sender.bundle.signingFingerprint else { throw PKIError.format("the message's from is not the sender's key") }
        guard to == recipient.fingerprint else { throw PKIError.format("the message's to is not the recipient's key") }
        return try PKI.seal(json, to: recipient, signedBy: sender)
    }

    /// What goes in an append lane's `payload`: the envelope text, base64 once more, as every lane holds it.
    public func lanePayload(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        LaneCrypto.lanePayload(encText: try seal(to: recipient, from: sender))
    }

    /// The same sealed message as text to hand over without an inbox (a QR code, a link, WhatsApp):
    /// `sgm1.` and base64url of the envelope JSON. Only the recipient's key opens it.
    public func sealedText(to recipient: PKIBundle, from sender: PKIIdentity) throws -> String {
        let encText = try seal(to: recipient, from: sender)
        guard let envelope = Data(base64Encoded: encText) else { throw PKIError.format("envelope") }
        return SealedText.prefix + PKI.base64url(envelope)
    }
}

/// How far a received message's sender is known.
public enum SenderTrust: String, Codable, Equatable, Sendable {
    /// Signed by a contact's key, and the signature checks.
    case contact
    /// Signed by the key of the card the message carries, which checks; the sender is not yet a contact.
    case cardInside = "card-inside"
    /// Signed by a key this device does not know, and no card came with it: unchecked, not forged.
    case unknown
    /// The signature, or the `from` and `to` inside, do not match: never shown as from anyone.
    case forged
    /// Not signed at all.
    case unsigned
}

/// A message opened on this device.
public struct OpenedMessage: Equatable, Sendable {
    public var message: PeopleMessage
    public var trust: SenderTrust
    /// The signing fingerprint the envelope names.
    public var signer: String?
    /// The card the message carries, checked, when it has one.
    public var card: ContactCard?

    public init(message: PeopleMessage, trust: SenderTrust, signer: String?, card: ContactCard?) {
        self.message = message
        self.trust = trust
        self.signer = signer
        self.card = card
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

    /// Opens an envelope text with `me`, checks the signature against `contacts` or, failing that, against
    /// the card inside, and checks `from` and `to`.
    public static func open(envelope encText: String, me: PKIIdentity, contacts: [PKIBundle]) throws -> OpenedMessage {
        let firstPass: PKIOpened
        do { firstPass = try PKI.unseal(encText, encryptPKCS8: me.encryptPKCS8, signers: contacts) } catch { throw OpenFailure.notForMe }
        guard let message = try? JSONDecoder().decode(PeopleMessage.self, from: firstPass.bytes) else {
            throw OpenFailure.notAMessage("not JSON of the message format")
        }
        if let first = message.problems.first { throw OpenFailure.notAMessage(first) }
        let card = message.card.flatMap { try? ContactCard.parse($0) }
        guard firstPass.signed, let signer = firstPass.signer else {
            return OpenedMessage(message: message, trust: .unsigned, signer: nil, card: card)
        }
        let trust: SenderTrust
        if let verified = firstPass.verified {
            trust = verified ? .contact : .forged
        } else if let card, card.signingFingerprint == signer {
            let againstCard = try PKI.unseal(encText, encryptPKCS8: me.encryptPKCS8, signers: [card.bundle])
            trust = againstCard.verified == true ? .cardInside : .forged
        } else {
            trust = .unknown
        }
        let addressed = message.from == signer && message.to == me.bundle.fingerprint
        return OpenedMessage(message: message, trust: addressed ? trust : .forged, signer: signer, card: card)
    }

    /// Opens what an append lane stored (`content`): base64 of the envelope text.
    public static func open(laneContent: String, me: PKIIdentity, contacts: [PKIBundle]) throws -> OpenedMessage {
        let encText: String
        do { encText = try LaneCrypto.encText(fromLaneContent: laneContent) } catch { throw OpenFailure.notForMe }
        return try open(envelope: encText, me: me, contacts: contacts)
    }
}

/// A sealed message handed over as text: `sgm1.<base64url of the envelope JSON>`.
public enum SealedText {
    public static let prefix = "sgm1."
    /// A page on the site that holds a sealed message in the address after `#`; it cannot open it.
    public static let linkBase = "https://ios.app.voicedebrief.ai/sealed/"

    /// The envelope text inside `text`, which may be a bare code, a link, or a message with one in it.
    public static func envelope(in text: String) -> String? {
        guard let start = text.range(of: prefix) else { return nil }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        var code = ""
        for c in text[start.upperBound...].utf8 {
            guard allowed.contains(c) else { break }
            code.unicodeScalars.append(Unicode.Scalar(c))
        }
        guard let json = PKI.data(base64url: code), json.first == UInt8(ascii: "{") else { return nil }
        return json.base64EncodedString()
    }

    public static func link(_ sealedText: String) -> String { linkBase + "#" + sealedText }
}
