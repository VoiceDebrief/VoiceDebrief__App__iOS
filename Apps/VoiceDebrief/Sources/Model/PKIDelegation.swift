import CryptoKit
import Foundation

/// "Sign in with pki.sgit.ai", from the asking side, as delegation.js and sso.js at pki.sgit.ai define it.
/// There is no server in between:
///
///   1. the client makes a key pair and sends the person to
///      `https://pki.sgit.ai/authorize/index.html#r=<base64url of the request JSON>`
///      request   { v: 1, kind: "pki.sgit.ai/authorize/v1", client, return, key, can, days, nonce, label }
///   2. the person, signed in there with their passkey, signs a delegation with their own key
///      delegation { v, kind: "pki.sgit.ai/delegation/v1", iss, iss_name, to, key, aud, can, from, until, check, nonce, sig }
///   3. and is sent back to `return#pki=<base64url of JSON { kind, nonce, identity, delegation }>`
///
/// This file builds the request, reads the answer and checks the delegation. The register's root is pinned
/// here, in code: it is never read from the register.
enum PKIDelegation {
    static let requestKind = "pki.sgit.ai/authorize/v1"
    static let authorizedKind = "pki.sgit.ai/authorized/v1"
    static let deniedKind = "pki.sgit.ai/denied/v1"
    static let delegationKind = "pki.sgit.ai/delegation/v1"

    /// The register's root, as published in pki.sgit.ai/llms.txt and /directory/anchors.json on 13 November 2026:
    /// the signing fingerprint of Dinis Cruz's record. Pinned. Changing it is a code change, reviewed as one.
    static let pinnedRoot = "sha256:db7f79fdd87e030a"

    static let authorizePage = "https://pki.sgit.ai/authorize/index.html"
    /// The asking site: the app's own, so that the answer comes back to an address iOS hands to the app.
    static let client = "https://ios.app.voicedebrief.ai"
    static let returnAddress = "https://ios.app.voicedebrief.ai/identity/return/"

    struct Request: Equatable, Sendable {
        var client: String
        var returnAddress: String
        var key: String
        var can: [String]
        var days: Int
        var nonce: String
        var label: String

        var json: PKIJSON {
            var fields: [String: PKIJSON] = [
                "v": .int(1), "kind": .string(requestKind), "client": .string(client), "return": .string(returnAddress),
                "key": .string(key), "can": .array(can.map { .string($0) }), "days": .int(days), "nonce": .string(nonce),
            ]
            if !label.isEmpty { fields["label"] = .string(label) }
            return .object(fields)
        }

        /// The address the person is sent to. Everything after `#` stays in their browser.
        var url: String { "\(authorizePage)#r=\(PKI.base64url(json.data))" }
    }

    static func newNonce() -> String {
        PKI.base64url(SymmetricKey(size: .init(bitCount: 192)).withUnsafeBytes { Data($0) })
    }

    /// A request for the key in `bundle` (whose code carries both of its public halves).
    /// `can` is what the delegation should allow; delegation.js accepts `identity`, `sign`, `sign:<word>`, `delegate`.
    static func request(for bundle: PKIBundle, can: [String] = ["identity", "sign:commit"], days: Int = 90, label: String,
                        nonce: String = newNonce(), client: String = client, returnAddress: String = returnAddress) throws -> Request {
        guard (1...365).contains(days) else { throw PKIError.format("days is 1 to 365") }
        guard !can.isEmpty, can.count <= 8, can.allSatisfy(isUse) else { throw PKIError.format("can is a list of up to 8 uses") }
        guard returnAddress.hasPrefix(client + "/") else { throw PKIError.format("the return address is not on the client's site") }
        return Request(client: client, returnAddress: returnAddress, key: try PKI.keyCode(bundle), can: can, days: days,
                       nonce: nonce, label: String(label.prefix(80)))
    }

    /// `identity`, `delegate`, `sign` or `sign:<1 to 32 of a-z, 0-9, ->`.
    static func isUse(_ text: String) -> Bool {
        if text == "identity" || text == "delegate" || text == "sign" { return true }
        guard text.hasPrefix("sign:") else { return false }
        let word = text.dropFirst(5)
        return (1...32).contains(word.utf8.count) && word.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
    }

    // MARK: The answer

    enum Answer: Equatable, Sendable {
        case authorized(nonce: String, identity: PKIJSON, delegation: PKIJSON)
        case denied(nonce: String)
    }

    enum Failure: Error, Equatable, LocalizedError {
        case noAnswer
        case unreadable
        case notAnAnswer
        case notAsked
        case notThisKey
        case notADelegation(String)
        case notThisSite(String)
        case notYet(String)
        case ended(String)
        case noIssuerKey
        case badSignature

        var errorDescription: String? {
            switch self {
            case .noAnswer: "There is no answer in that text: it should hold pki= and a long code."
            case .unreadable: "The answer does not read."
            case .notAnAnswer: "That is not a sign-in answer from pki.sgit.ai."
            case .notAsked: "An answer this app did not ask for: refused."
            case .notThisKey: "The delegation is not for this app's key."
            case .notADelegation(let why): "Not a delegation (\(why))."
            case .notThisSite(let site): "It was given to \(site), not to this app."
            case .notYet(let day): "Not valid before \(day)."
            case .ended(let day): "It ended on \(day)."
            case .noIssuerKey: "The answer does not carry the key that signed it, so the signature cannot be checked here."
            case .badSignature: "The issuer's signature does not check."
            }
        }
    }

    /// The answer in a return address, or in whatever was pasted: the text after `pki=`, or the bare code.
    static func answer(in text: String) throws -> Answer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = trimmed
        if let marker = trimmed.range(of: "pki=", options: .backwards) {
            code = String(trimmed[marker.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        }
        guard !code.isEmpty, let bytes = PKI.data(base64url: code) else { throw Failure.noAnswer }
        guard let value = try? PKIJSON(parsing: bytes), let kind = value["kind"]?.string, let nonce = value["nonce"]?.string else {
            throw Failure.unreadable
        }
        if kind == deniedKind { return .denied(nonce: nonce) }
        guard kind == authorizedKind, let delegation = value["delegation"], delegation.object != nil else { throw Failure.notAnAnswer }
        return .authorized(nonce: nonce, identity: value["identity"] ?? .null, delegation: delegation)
    }

    // MARK: Checking a delegation

    /// A delegation that checked, and how far.
    struct Checked: Equatable, Sendable {
        var issuer: String
        var issuerName: String
        var to: String
        var audience: String
        var can: [String]
        var from: String
        var until: String
        var live: Bool
        var id: String
        /// True when the issuer is the pinned root itself. Any other issuer has to chain to the root through the
        /// register's links, which this build does not walk: it says so instead of guessing.
        var issuerIsPinnedRoot: Bool
    }

    private static func isDay(_ text: String) -> Bool {
        let u = Array(text.utf8)
        guard u.count == 10, u[4] == 0x2D, u[7] == 0x2D else { return false }
        return [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy { u[$0] >= 0x30 && u[$0] <= 0x39 }
    }

    /// delegation.js `shape`, then what `checkDelegation` checks without the register: the audience, the dates,
    /// that the key it carries is the key it names, and the issuer's signature.
    ///
    /// - Parameters:
    ///   - issuerBundle: the issuer's public bundle, from anywhere: it is used only if its signing fingerprint is
    ///     the `iss` the delegation names, and a fingerprint is the hash of the key, so nothing is taken on trust.
    ///   - audience: the site the delegation must be for. Nil skips the check.
    ///   - today: `yyyy-mm-dd`, the day it is judged on.
    static func check(_ d: PKIJSON, issuerBundle: PKIBundle?, audience: String? = client, today: String) throws -> Checked {
        let allowed: Set<String> = ["v", "kind", "iss", "iss_name", "to", "key", "aud", "can", "from", "until", "check", "nonce", "sig"]
        guard let fields = d.object, fields.keys.allSatisfy(allowed.contains) else { throw Failure.notADelegation("fields it should not carry") }
        guard d["v"] == .int(1), d["kind"] == .string(delegationKind) else { throw Failure.notADelegation("version or kind") }
        guard let iss = d["iss"]?.string, let to = d["to"]?.string, PKI.isFingerprint(iss), PKI.isFingerprint(to) else {
            throw Failure.notADelegation("iss and to are key fingerprints")
        }
        guard let aud = d["aud"]?.string, aud.hasPrefix("https://") || aud.hasPrefix("http://localhost") || aud.hasPrefix("http://127.0.0.1") else {
            throw Failure.notADelegation("aud is an origin")
        }
        guard let can = d["can"]?.array?.compactMap(\.string), can.count == d["can"]?.array?.count, can.allSatisfy(isUse) else {
            throw Failure.notADelegation("can is a list of uses")
        }
        guard let from = d["from"]?.string, let until = d["until"]?.string, isDay(from), isDay(until), until >= from else {
            throw Failure.notADelegation("from and until are dates")
        }
        guard let mode = d["check"]?.string, mode == "live" || mode == "offline" else { throw Failure.notADelegation("check is live or offline") }
        if let audience, aud != audience { throw Failure.notThisSite(aud) }
        if today < from { throw Failure.notYet(from) }
        if today > until { throw Failure.ended(until) }
        guard let code = d["key"]?.string, let carried = PKI.parseKeyCode(code), carried.signingFingerprint == to else {
            throw Failure.notADelegation("the key it carries is not the key it names")
        }
        guard let issuerBundle, issuerBundle.signingFingerprint == iss, let spki = try? PKI.publicDER(issuerBundle.sign),
              LaneCrypto.fingerprint(spki: spki) == iss else { throw Failure.noIssuerKey }
        guard PKI.verifyStatement(d, signPEM: issuerBundle.sign) else { throw Failure.badSignature }
        return Checked(issuer: iss, issuerName: d["iss_name"]?.string ?? "", to: to, audience: aud, can: can, from: from, until: until,
                       live: mode == "live", id: PKI.statementId(d), issuerIsPinnedRoot: iss == pinnedRoot)
    }

    /// The whole return: the answer must be the one asked for (its nonce), for this key, and its delegation must check.
    /// The issuer's bundle is looked for in the answer's `identity`; `issuerBundle` is used when it is not there.
    static func accept(_ text: String, asked request: Request, key: PKIBundle, issuerBundle: PKIBundle? = nil,
                       today: String) throws -> (checked: Checked, delegation: PKIJSON, identity: PKIJSON) {
        switch try answer(in: text) {
        case .denied(let nonce):
            guard nonce == request.nonce else { throw Failure.notAsked }
            throw Failure.notAnAnswer
        case .authorized(let nonce, let identity, let delegation):
            guard nonce == request.nonce, delegation["nonce"] == .string(nonce) else { throw Failure.notAsked }
            guard delegation["to"] == .string(key.signingFingerprint) else { throw Failure.notThisKey }
            let carried = bundle(in: identity)
            let checked = try check(delegation, issuerBundle: carried ?? issuerBundle, audience: request.client, today: today)
            return (checked, delegation, identity)
        }
    }

    /// A public bundle inside the answer's `identity`, wherever that page put it.
    static func bundle(in identity: PKIJSON) -> PKIBundle? {
        if let direct = try? PKIBundle(json: identity) { return direct }
        if let inner = identity["bundle"], let made = try? PKIBundle(json: inner) { return made }
        if let code = identity["key"]?.string ?? identity["code"]?.string, let made = PKI.parseKeyCode(code) { return made }
        return nil
    }

    /// The line the app shows for a delegation that checked.
    static func summary(_ c: Checked) -> String {
        let who = c.issuerName.isEmpty ? c.issuer : "\(c.issuerName) (\(c.issuer))"
        let root = c.issuerIsPinnedRoot
            ? "That key is the register's root, which this app pins."
            : "Whether the register's root vouches for that key is not checked by this build."
        return "Signed by a key that \(who) in the register vouched for, until \(c.until). \(root)"
    }
}
