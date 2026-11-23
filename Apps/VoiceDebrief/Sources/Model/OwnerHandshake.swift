import CryptoKit
import Foundation
import SGitPeople

/// The handshake that makes owner mode exist only for the owner (R6: "the app has its own identity, which
/// Dinis registers with his key by a handshake").
///
/// 1. **The request**, made on the device: `or1.<json>.<signature>`. The JSON names this install's device key
///    (issue 018: a P-256 key in the Secure Enclave, wiped on reinstall), and the device key signs it, so whoever
///    grants knows the request came from the holder of that key.
/// 2. **The grant**, made by the owner on his own machine with his sgit key: `tools/owner/grant.py` checks the
///    request, writes `owner.grant/v1` naming the device key, signs the file with `sgit pki sign` (the stock
///    detached signature) and prints `og1.<envelope>`, the grant, its `.sig` and his public bundle.
/// 3. **The check**, on the device: the signature is the bundle's, the bundle is sound, its signing fingerprint
///    is one this build pins as the owner's, and the grant names this device's key and this app.
///
/// Nothing here is secret: a request, a grant and a public bundle can be shown to anyone. What makes it the
/// owner's is the pinned fingerprint, and the private key that only he holds.
enum OwnerHandshake {
    static let app = "ai.voicedebrief.app"
    static let requestKind = "owner.request/v1"
    static let grantKind = "owner.grant/v1"
    static let requestPrefix = "or1."
    static let grantPrefix = "og1."

    /// The signing fingerprints of the owner's key: the only keys whose grant opens owner mode. Empty until the
    /// owner gives his (a public value: `sgit pki list` shows it). While empty, no grant is accepted and owner
    /// mode stays on its demo.
    static let pinnedOwners: [String] = []

    struct Request: Codable, Equatable, Sendable {
        var kind: String
        var app: String
        var device: String          // the device key's fingerprint
        var deviceKey: String       // its public key, PEM
        var kept: String            // "secure-enclave" or "keychain-this-device"
        var label: String           // the device's name, for the owner to recognise it
        var at: String
        var nonce: String
    }

    struct Grant: Codable, Equatable, Sendable {
        var kind: String
        var app: String
        var device: String          // the device key's fingerprint, from the request
        var request: String         // sha256: of the request's bytes
        var owner: String           // the owner's signing fingerprint
        var granted: String
        var note: String?
    }

    /// What `og1.` carries: the grant file's bytes, the `.sig` that `sgit pki sign` wrote for them, and the
    /// owner's public bundle as `sgit pki export` prints it.
    struct Envelope: Codable, Equatable, Sendable {
        var grant: String           // base64 of the grant file's exact bytes
        var sig: String             // the .sig file's text
        var owner: PKIBundle
    }

    struct Accepted: Equatable, Sendable {
        var grant: Grant
        var owner: PKIBundle
    }

    enum Failure: LocalizedError, Equatable {
        case notARequest, notAGrant, badSignature, unsoundOwnerKey, ownerNotPinned(String)
        case wrongKind, otherApp, otherDevice, ownerMismatch, noOwnerPinned

        var errorDescription: String? {
            switch self {
            case .notARequest: "Not a registration request."
            case .notAGrant: "Not an owner grant (it starts og1.)."
            case .badSignature: "The signature does not match: the grant was changed, or signed by another key."
            case .unsoundOwnerKey: "The owner's key in the grant is not a sound sgit key."
            case .ownerNotPinned(let fp): "Signed by \(fp), which is not the owner's key this build knows."
            case .wrongKind: "Not an owner.grant/v1."
            case .otherApp: "The grant is for another app."
            case .otherDevice: "The grant is for another device, or for this device before the app was reinstalled."
            case .ownerMismatch: "The grant names a different owner from the key that signed it."
            case .noOwnerPinned: "This build does not know the owner's key yet, so no grant can be accepted."
            }
        }
    }

    // MARK: The request

    static func request(deviceKeyPEM: String, fingerprint: String, kept: String, label: String, at: Date, nonce: String,
                        sign: (Data) throws -> Data) throws -> String {
        let body = Request(kind: requestKind, app: app, device: fingerprint, deviceKey: deviceKeyPEM, kept: kept,
                           label: label, at: ISO8601DateFormatter().string(from: at), nonce: nonce)
        let bytes = try encoder.encode(body)
        let signature = try sign(bytes)
        return requestPrefix + PKI.base64url(bytes) + "." + PKI.base64url(signature)
    }

    /// Reads a request and checks that its device key signed it and that the fingerprint is that key's.
    static func readRequest(_ text: String) throws -> (request: Request, bytes: Data) {
        guard let range = text.range(of: #"or1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, options: .regularExpression) else { throw Failure.notARequest }
        let parts = text[range].dropFirst(requestPrefix.count).split(separator: ".")
        guard parts.count == 2, let bytes = PKI.data(base64url: String(parts[0])), let signature = PKI.data(base64url: String(parts[1])),
              let request = try? JSONDecoder().decode(Request.self, from: bytes), request.kind == requestKind else { throw Failure.notARequest }
        guard let spki = try? PKI.publicDER(request.deviceKey), LaneCrypto.fingerprint(spki: spki) == request.device,
              PKI.verify(signature: signature, over: bytes, signSPKI: spki) else { throw Failure.badSignature }
        return (request, bytes)
    }

    static func requestId(_ bytes: Data) -> String {
        "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The grant

    /// Checks a grant for this device against the pinned owner keys.
    static func verify(_ text: String, deviceFingerprint: String, pinned: [String] = pinnedOwners) throws -> Accepted {
        guard let range = text.range(of: #"og1\.[A-Za-z0-9_-]+"#, options: .regularExpression),
              let data = PKI.data(base64url: String(text[range].dropFirst(grantPrefix.count))),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let bytes = Data(base64Encoded: envelope.grant) else { throw Failure.notAGrant }
        guard PKI.problems(of: envelope.owner).isEmpty else { throw Failure.unsoundOwnerKey }
        guard PKI.verifyDetached(envelope.sig, over: bytes, by: envelope.owner) else { throw Failure.badSignature }
        guard !pinned.isEmpty else { throw Failure.noOwnerPinned }
        guard pinned.contains(envelope.owner.signingFingerprint) else { throw Failure.ownerNotPinned(envelope.owner.signingFingerprint) }
        guard let grant = try? JSONDecoder().decode(Grant.self, from: bytes), grant.kind == grantKind else { throw Failure.wrongKind }
        guard grant.app == app else { throw Failure.otherApp }
        guard grant.owner == envelope.owner.signingFingerprint else { throw Failure.ownerMismatch }
        guard grant.device == deviceFingerprint else { throw Failure.otherDevice }
        return Accepted(grant: grant, owner: envelope.owner)
    }

    /// Makes a grant the way `tools/owner/grant.py` does, for the tests (and for an owner key held in the app).
    static func grant(for request: Request, requestBytes: Data, by owner: PKIIdentity, at: Date, note: String? = nil) throws -> String {
        let grant = Grant(kind: grantKind, app: request.app, device: request.device, request: requestId(requestBytes),
                          owner: owner.bundle.signingFingerprint, granted: ISO8601DateFormatter().string(from: at), note: note)
        let bytes = try encoder.encode(grant)
        let envelope = Envelope(grant: bytes.base64EncodedString(), sig: try PKI.detachedSignature(over: bytes, by: owner), owner: owner.bundle)
        return grantPrefix + PKI.base64url(try encoder.encode(envelope))
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
