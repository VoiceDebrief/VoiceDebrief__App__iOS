import Foundation
// The PKI interop tool compiles this file with the package's PKI files as one module, where there is nothing to import.
#if canImport(SGitPeople)
import SGitPeople
#endif

/// The statement that links a device key to a person: "this device key is mine, from this date, for these uses".
/// It is written in the register's statement envelope (pki.sgit.ai: `{ v, type, registry, record, signer,
/// created_at, body, sig }`) and signed the same way, so pki.sgit.ai's `verifyStatement` checks it as it is:
///
///     { "v": 1, "type": "device", "registry": "voicedebrief.ai/vault",
///       "record": <the user's signing fingerprint>, "signer": <the same>, "created_at": "2026-11-13T10:00:00Z",
///       "body": { "kind": "voicedebrief.ai/device/v1",
///                 "key": <the device's public key, PEM>, "key_fingerprint": "sha256:…", "key_id": "key-rnd-imm-…",
///                 "name": "an iPhone", "kept": "secure-enclave", "from": "2026-11-13", "can": ["commit"],
///                 "bundle": <the user's public bundle> },
///       "sig": <base64 of r‖s over the canonical bytes> }
///
/// It carries the user's public bundle, so a reader holding only the vault can check the signature. What the
/// statement cannot say is whose the user key is: that comes from comparing its fingerprint, or from a register.
/// A reader checks a commit in two steps: the device key signed the commit; this statement, signed by the
/// user's key, names that device key.
enum IdentityVouch {
    static let registry = "voicedebrief.ai/vault"
    static let type = "device"
    static let kind = "voicedebrief.ai/device/v1"
    static let folder = "identity/devices"

    /// Where the statement is kept in a vault: one file per device key.
    static func path(deviceFingerprint: String) -> String {
        "\(folder)/\(deviceFingerprint.replacingOccurrences(of: ":", with: "-")).json"
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    static func day(_ date: Date) -> String { String(timestamp(date).prefix(10)) }

    /// The device, as the statement describes it. Nothing here is secret.
    struct Device: Equatable, Sendable {
        var publicKeyPEM: String
        var keyId: String
        var name: String
        var kept: String

        var fingerprint: String? {
            (try? PKI.publicDER(publicKeyPEM)).map { LaneCrypto.fingerprint(spki: $0) }
        }
    }

    /// The statement before it is signed.
    static func statement(for device: Device, by user: PKIBundle, at date: Date, can: [String] = ["commit"]) throws -> PKIJSON {
        guard let fingerprint = device.fingerprint, (try? PKI.signingPublicKey(spki: PKI.publicDER(device.publicKeyPEM))) != nil else {
            throw PKIError.key("the device key is not a P-256 public key")
        }
        return .object([
            "v": .int(1), "type": .string(type), "registry": .string(registry),
            "record": .string(user.signingFingerprint), "signer": .string(user.signingFingerprint),
            "created_at": .string(timestamp(date)),
            "body": .object([
                "kind": .string(kind), "key": .string(device.publicKeyPEM), "key_fingerprint": .string(fingerprint),
                "key_id": .string(device.keyId), "name": .string(device.name), "kept": .string(device.kept),
                "from": .string(day(date)), "can": .array(can.map { .string($0) }), "bundle": user.asJSON,
            ]),
        ])
    }

    /// Signed by the user's key.
    static func make(for device: Device, by user: PKIIdentity, at date: Date = Date()) throws -> PKIJSON {
        try PKI.signStatement(try statement(for: device, by: user.bundle, at: date), signPKCS8: user.signPKCS8)
    }

    /// The file's bytes: canonical JSON and a newline, so the file is the same wherever it is written.
    static func fileData(_ statement: PKIJSON) -> Data { Data((statement.canonical + "\n").utf8) }

    /// What a checked statement says.
    struct Checked: Equatable, Sendable {
        var user: PKIBundle
        var deviceFingerprint: String
        var deviceKeyPEM: String
        var keyId: String
        var name: String
        var kept: String
        var from: String
        var can: [String]
        var createdAt: String
    }

    enum Failure: Error, Equatable, LocalizedError {
        case notAStatement(String)
        case badBundle(String)
        case notTheSigner
        case badSignature
        case badDeviceKey

        var errorDescription: String? {
            switch self {
            case .notAStatement(let why): "This is not a device statement (\(why))."
            case .badBundle(let why): "The key bundle it carries is not sound: \(why)."
            case .notTheSigner: "It names one key as its signer and carries another."
            case .badSignature: "The signature does not check: changed after it was signed, or not that key."
            case .badDeviceKey: "The device key it names is not the key it carries."
            }
        }
    }

    /// Checks a statement from its own contents: its shape, the bundle it carries, that the bundle's signing key
    /// is the signer it names, the signature, and that the device fingerprint is the device key's.
    static func check(_ statement: PKIJSON) throws -> Checked {
        guard statement["v"] == .int(1), statement["type"] == .string(type), statement["registry"] == .string(registry) else {
            throw Failure.notAStatement("version, type or registry")
        }
        guard let body = statement["body"], body["kind"] == .string(kind), let bundleValue = body["bundle"],
              let key = body["key"]?.string, let keyFingerprint = body["key_fingerprint"]?.string,
              let keyId = body["key_id"]?.string, let from = body["from"]?.string,
              let can = body["can"]?.array?.compactMap(\.string), let signer = statement["signer"]?.string,
              let createdAt = statement["created_at"]?.string else { throw Failure.notAStatement("a field is missing") }
        guard let bundle = try? PKIBundle(json: bundleValue) else { throw Failure.badBundle("it does not read") }
        let problems = PKI.problems(of: bundle).filter { !$0.contains("-bit") }
        if let first = problems.first { throw Failure.badBundle(first) }
        guard signer == bundle.signingFingerprint, statement["record"] == .string(signer) else { throw Failure.notTheSigner }
        guard PKI.verifyStatement(statement, signPEM: bundle.sign) else { throw Failure.badSignature }
        guard let der = try? PKI.publicDER(key), (try? PKI.signingPublicKey(spki: der)) != nil,
              LaneCrypto.fingerprint(spki: der) == keyFingerprint else { throw Failure.badDeviceKey }
        return Checked(user: bundle, deviceFingerprint: keyFingerprint, deviceKeyPEM: key, keyId: keyId,
                       name: body["name"]?.string ?? "", kept: body["kept"]?.string ?? "", from: from, can: can, createdAt: createdAt)
    }

    static func check(file data: Data) throws -> Checked {
        guard let value = try? PKIJSON(parsing: data) else { throw Failure.notAStatement("not JSON") }
        return try check(value)
    }

    /// Whether a checked statement speaks for the key that signed a commit: the same key, compared by its bytes.
    static func covers(_ checked: Checked, commitKeyPEM: String) -> Bool {
        guard let a = try? PKI.publicDER(checked.deviceKeyPEM), let b = try? PKI.publicDER(commitKeyPEM) else { return false }
        return a == b && checked.can.contains("commit")
    }
}
