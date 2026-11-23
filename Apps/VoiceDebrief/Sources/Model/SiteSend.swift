import CryptoKit
import Foundation
import SGitPeople

/// Talking to a Sovereign Website's keeper from the app (R7, tier 1: "do you want to make a change to the website?
/// Just speak here, and then the agent will come back to you"). The formats are the site's own `/send/` page's
/// (`send.js` and `keyring.js` of Site__Organisation__Chiswick-Cheese-Market at 65002f9), so the keeper cannot tell
/// the app from the browser:
///
/// - **inbox.json** (`SiteInbox`): where the keeper's lane is and its public key.
/// - **The person's key** (`SitePersonKey`): the key a keeper issues to its person, a link whose `#key=` fragment
///   is base64url of `{"p": person, "f": fingerprint, "e": [d, x, y], "s": [d, x, y]}` (P-256, JWK fields).
/// - **A request** (`ccm.request/v1`): `{type, to, site, sent_at, from, signed: {person, key, alg, sig}, items_json}`,
///   the signature ECDSA P-256 SHA-256 in P1363 form (raw r‖s), base64, over the exact `items_json` text. Sealed with
///   sgit's hybrid envelope v2 (`LaneCrypto`, byte-compatible) and appended to the keeper's lane.
/// - **A reply** (`ws-ecies-1`): an ephemeral P-256 key (`epk`, a JWK), ECDH with the person's key, HKDF-SHA-256 with
///   an empty salt and the info `ws-ecies-1`, AES-256-GCM (`iv`, `ct` with its tag at the end, both base64).
enum SiteSend {
    static let requestType = "ccm.request/v1"
    static let alg = "ECDSA-P256-SHA256-P1363"
    static let eciesInfo = "ws-ecies-1"

    /// The form JavaScript's `toISOString()` writes: 2026-11-23T19:00:00.000Z.
    static func isoMillis(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    enum Failure: LocalizedError, Equatable {
        case notAKeyLink, badKey, notAnInbox, sealedToAnotherKey(String), cannotOpen

        var errorDescription: String? {
            switch self {
            case .notAKeyLink: "That is not a key link (it has key= and a long code)."
            case .badKey: "The key arrived incomplete or changed: copy the whole link again, from the start to the end."
            case .notAnInbox: "This site has no keeper's inbox (send/inbox.json)."
            case .sealedToAnotherKey(let fp): "This reply is sealed to \(fp), not to the key on this device."
            case .cannotOpen: "This reply could not be opened with the key on this device."
            }
        }
    }
}

/// The keeper's inbox, as the site publishes it at `send/inbox.json`. Nothing in it is secret: the token can only append.
struct SiteInbox: Codable, Equatable, Sendable {
    struct Recipient: Codable, Equatable, Sendable {
        var fingerprint: String
        var signing_fingerprint: String?
        var encrypt: String
    }
    var agent: String
    var site: String
    var endpoint: String
    var vault_id: String
    var append_token: String
    var recipient: Recipient

    /// The keeper's lane, in the form the app already sends on.
    func lane() throws -> DeveloperLane {
        guard let spki = try? PKI.publicDER(recipient.encrypt), LaneCrypto.fingerprint(spki: spki) == recipient.fingerprint
        else { throw LaneCrypto.Failure.fingerprintMismatch }
        return DeveloperLane(vault: vault_id, token: append_token, publicKeyPEM: recipient.encrypt, fingerprint: recipient.fingerprint)
    }

    static func decode(_ data: Data) throws -> SiteInbox {
        guard let inbox = try? JSONDecoder().decode(SiteInbox.self, from: data) else { throw SiteSend.Failure.notAnInbox }
        return inbox
    }
}

/// The person's key, as the keeper issues it. Secret: kept in the Keychain, never shown again once taken.
struct SitePersonKey: Equatable {
    var person: String
    var fingerprint: String
    var packed: String          // the code from the link, as it came: what the Keychain keeps
    let agreement: P256.KeyAgreement.PrivateKey
    let signing: P256.Signing.PrivateKey

    static func == (a: SitePersonKey, b: SitePersonKey) -> Bool { a.packed == b.packed }

    /// From a key link (`…#key=<code>`), a pasted link, or the bare code.
    static func from(link text: String) throws -> SitePersonKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let code: String
        if let range = trimmed.range(of: #"key=[A-Za-z0-9_-]+"#, options: .regularExpression) {
            code = String(trimmed[range].dropFirst(4))
        } else if trimmed.range(of: #"^[A-Za-z0-9_-]{100,}$"#, options: .regularExpression) != nil {
            code = trimmed
        } else {
            throw SiteSend.Failure.notAKeyLink
        }
        return try unpack(code)
    }

    static func unpack(_ code: String) throws -> SitePersonKey {
        struct Packed: Decodable { var p: String; var f: String; var e: [String]; var s: [String] }
        guard let data = PKI.data(base64url: code), let packed = try? JSONDecoder().decode(Packed.self, from: data),
              packed.e.count == 3, packed.s.count == 3,
              let ed = PKI.data(base64url: packed.e[0]), let sd = PKI.data(base64url: packed.s[0]),
              let agreement = try? P256.KeyAgreement.PrivateKey(rawRepresentation: ed),
              let signing = try? P256.Signing.PrivateKey(rawRepresentation: sd),
              Self.matches(agreement.publicKey.x963Representation, x: packed.e[1], y: packed.e[2]),
              Self.matches(signing.publicKey.x963Representation, x: packed.s[1], y: packed.s[2])
        else { throw SiteSend.Failure.badKey }
        return SitePersonKey(person: packed.p, fingerprint: packed.f, packed: code, agreement: agreement, signing: signing)
    }

    /// The public point in the JWK is the one the private scalar makes: a key changed on the way fails here.
    private static func matches(_ x963: Data, x: String, y: String) -> Bool {
        guard x963.count == 65, let xd = PKI.data(base64url: x), let yd = PKI.data(base64url: y) else { return false }
        return x963.dropFirst().prefix(32) == xd && x963.suffix(32) == yd
    }

    // MARK: A request

    /// The request the site's `send()` makes, as bytes to be sealed. `items_json` is signed as the exact text sent.
    func request(kind: String, text: String, inbox: SiteInbox, site: String, at: Date) throws -> Data {
        struct Items: Encodable { var kind: String; var text: String; var images: [String] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let itemsJSON = String(decoding: try encoder.encode(Items(kind: kind, text: text, images: [])), as: UTF8.self)
        let sig = try signing.signature(for: Data(itemsJSON.utf8)).rawRepresentation.base64EncodedString()
        let object: [String: Any] = [
            "type": SiteSend.requestType, "to": inbox.agent, "site": site, "sent_at": SiteSend.isoMillis(at),
            "from": person, "signed": ["person": person, "key": fingerprint, "alg": SiteSend.alg, "sig": sig], "items_json": itemsJSON,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: A reply

    struct Envelope: Codable, Equatable, Sendable {
        struct JWK: Codable, Equatable, Sendable { var kty: String?; var crv: String?; var x: String; var y: String }
        var v: Int?
        var to: String?
        var key: String?
        var at: String?
        var epk: JWK
        var iv: String
        var ct: String
    }

    /// Opens one reply sealed to this key. What is inside is the keeper's JSON (`{at, re, text}` on the site).
    func open(_ envelope: Envelope) throws -> Data {
        if let sealedTo = envelope.key ?? envelope.to, sealedTo.hasPrefix("sha256:"), sealedTo != fingerprint {
            throw SiteSend.Failure.sealedToAnotherKey(sealedTo)
        }
        guard let x = PKI.data(base64url: envelope.epk.x), let y = PKI.data(base64url: envelope.epk.y), x.count == 32, y.count == 32,
              let epk = try? P256.KeyAgreement.PublicKey(x963Representation: Data([0x04]) + x + y),
              let iv = Data(base64Encoded: envelope.iv), let ct = Data(base64Encoded: envelope.ct), ct.count >= 16,
              let shared = try? agreement.sharedSecretFromKeyAgreement(with: epk) else { throw SiteSend.Failure.cannotOpen }
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data(SiteSend.eciesInfo.utf8), outputByteCount: 32)
        guard let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ct.dropLast(16), tag: ct.suffix(16)),
              let plain = try? AES.GCM.open(box, using: key) else { throw SiteSend.Failure.cannotOpen }
        return plain
    }
}

/// A reply as the keeper writes it inside the envelope.
struct SiteReply: Codable, Equatable, Sendable, Identifiable {
    var at: String?
    var re: String?
    var text: String
    var id: String { (at ?? "") + "|" + text.prefix(40) }
}
