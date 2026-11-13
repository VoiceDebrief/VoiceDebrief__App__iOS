import CryptoKit
import Foundation
#if canImport(VoiceDebrief)
@testable import VoiceDebrief
#endif

/// What Swift must be able to read of what sgit and pki.sgit.ai's keys.js make. One set of checks, run twice:
/// by the app's tests against the fixtures committed in `Tests/PKIFixtures/`, and by `scripts/pki-interop`
/// in `pki-interop.yml` against files those tools made minutes earlier in the same run.
/// A fixture is a flat JSON object of strings, written by `sgit_make.py` and `keysjs_make.mjs`.
enum PKIFixtureChecks {
    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    static func need(_ ok: Bool, _ what: String) throws {
        if !ok { throw Failed(description: "not true: \(what)") }
    }

    static func field(_ f: [String: String], _ name: String) throws -> String {
        guard let value = f[name] else { throw Failed(description: "the fixture has no \(name)") }
        return value
    }

    static func load(_ data: Data) throws -> [String: String] {
        guard let any = try? JSONSerialization.jsonObject(with: data), let dict = any as? [String: String] else {
            throw Failed(description: "a fixture is one JSON object of strings")
        }
        return dict
    }

    /// `{ bundle, private: { encrypt, sign } (base64 PKCS#8), created }`, as keys.js keeps an identity.
    static func identity(_ text: String) throws -> PKIIdentity {
        let value = try PKIJSON(parsing: Data(text.utf8))
        guard let bundleValue = value["bundle"], let encrypt = value["private"]?["encrypt"]?.string, let sign = value["private"]?["sign"]?.string,
              let e = Data(base64Encoded: encrypt), let s = Data(base64Encoded: sign) else { throw Failed(description: "not an identity") }
        return PKIIdentity(bundle: try PKIBundle(json: bundleValue), encryptPKCS8: e, signPKCS8: s, created: Date(timeIntervalSince1970: 0))
    }

    /// What `sgit pki` made: a key store, an exported bundle, a detached signature, two envelopes.
    static func sgit(_ f: [String: String]) throws -> [String] {
        var done: [String] = []
        let bundle = try PKIBundle(json: try PKIJSON(parsing: Data(try field(f, "bundle").utf8)))
        try need(PKI.problems(of: bundle).isEmpty, "sgit's exported bundle is sound: \(PKI.problems(of: bundle))")
        done.append("sgit's bundle reads and both fingerprints are its keys' (\(bundle.fingerprint), \(bundle.signingFingerprint))")

        let passphrase = try field(f, "passphrase")
        let identity = try PKI.importKeystore(privateKeyPEM: try field(f, "private_key.pem"), signingPrivatePEM: try field(f, "signing_private.pem"),
                                              passphrase: passphrase, label: bundle.label)
        try need(identity.bundle == bundle, "the public halves recomputed from sgit's private keys are the exported bundle")
        done.append("sgit's passphrase-protected private keys open (PBES2) and give back the same public bundle")
        try need((try? PKI.decryptPrivate(try field(f, "signing_private.pem"), passphrase: passphrase + "x")) == nil, "a wrong passphrase is refused")

        let message = Data(try field(f, "message").utf8)
        let sig = try field(f, "message.sig")
        try need(PKI.verifyDetached(sig, over: message, by: bundle), "sgit's detached signature verifies")
        try need(!PKI.verifyDetached(sig, over: message + Data([0x21]), by: bundle), "it does not verify over other bytes")
        done.append("sgit's detached signature verifies, and not over changed bytes")

        let signed = try PKI.unseal(try field(f, "to-self.enc"), encryptPKCS8: identity.encryptPKCS8, signers: [bundle])
        try need(signed.bytes == message, "sgit's signed envelope opens to the message")
        try need(signed.signed && signed.signer == bundle.signingFingerprint && signed.verified == true, "its signature is sgit's key's")
        let plain = try PKI.unseal(try field(f, "unsigned.enc"), encryptPKCS8: identity.encryptPKCS8)
        try need(plain.bytes == message && !plain.signed && plain.verified == nil, "sgit's unsigned envelope opens, and is not called signed")
        done.append("sgit's envelopes open with its private key; the signed one's signature checks")

        let code = try PKI.keyCode(bundle)
        try need(PKI.parseKeyCode("https://pki.sgit.ai/send/#" + code) == bundle, "the k1 code of sgit's bundle reads back to it")
        return done
    }

    /// What keys.js, message.js and delegation.js made.
    static func keysjs(_ f: [String: String]) throws -> [String] {
        var done: [String] = []
        let person = try identity(try field(f, "identity"))
        try need(PKI.problems(of: person.bundle).isEmpty, "keys.js's bundle is sound: \(PKI.problems(of: person.bundle))")
        try need(try PKI.bundle(encryptPKCS8: person.encryptPKCS8, signPKCS8: person.signPKCS8, label: person.bundle.label) == person.bundle,
                 "the public halves recomputed from WebCrypto's PKCS#8 keys are the bundle")
        done.append("WebCrypto's PKCS#8 private keys read, and give back keys.js's bundle (\(person.bundle.signingFingerprint))")

        let code = try field(f, "k1")
        try need(PKI.parseKeyCode(code) == person.bundle, "keys.js's k1 code reads to its bundle")
        try need(try PKI.keyCode(person.bundle) == code, "Swift writes the same k1 code")
        done.append("the k1 key code reads and is written identically")

        let passphrase = try field(f, "passphrase")
        try need(try PKI.decryptPrivate(try field(f, "signing_private.pem"), passphrase: passphrase) == person.signPKCS8, "keys.js's encrypted signing key opens")
        try need(try PKI.decryptPrivate(try field(f, "private_key.pem"), passphrase: passphrase) == person.encryptPKCS8, "keys.js's encrypted encryption key opens")
        done.append("keys.js's passphrase-protected private keys open")

        guard let cases = try PKIJSON(parsing: Data(try field(f, "canon_cases").utf8)).array else { throw Failed(description: "canon_cases is a list") }
        for (n, c) in cases.enumerated() {
            guard let value = c["value"], let canon = c["canon"]?.string else { throw Failed(description: "canon case \(n)") }
            try need(value.canonical == canon, "canonical form of case \(n): Swift wrote \(value.canonical), keys.js wrote \(canon)")
        }
        done.append("\(cases.count) canonical forms match keys.js's byte for byte")

        let statement = try PKIJSON(parsing: Data(try field(f, "statement").utf8))
        try need(String(decoding: PKI.canonicalBytes(statement), as: UTF8.self) == (try field(f, "statement_canonical")), "the statement's canonical bytes are keys.js's")
        try need(PKI.statementId(statement) == (try field(f, "statement_id")), "the statement id is keys.js's")
        try need(PKI.verifyStatement(statement, signPEM: person.bundle.sign), "keys.js's statement signature verifies")
        var changed = statement
        changed["created_at"] = .string("2026-11-13T10:00:01Z")
        try need(!PKI.verifyStatement(changed, signPEM: person.bundle.sign), "a changed statement does not verify")
        let again = try PKI.signStatement(statement, signPKCS8: person.signPKCS8)
        try need(PKI.verifyStatement(again, signPEM: person.bundle.sign), "Swift signs a statement with keys.js's key and it verifies")
        done.append("a keys.js statement: canonical bytes, id and signature all check; a changed one does not")

        let opened = try PKI.unseal(try field(f, "sealed.enc"), encryptPKCS8: person.encryptPKCS8, signers: [person.bundle])
        try need(opened.bytes == Data(try field(f, "sealed_text").utf8) && opened.verified == true, "keys.js's sealed message opens and its signature checks")
        done.append("keys.js's sealed envelope opens")

        // The sign-in: the request sso.js sends, the delegation authorize.js signs, the answer it sends back.
        let browser = try identity(try field(f, "browser"))
        let requestValue = try PKIJSON(parsing: Data(try field(f, "request").utf8))
        guard let nonce = requestValue["nonce"]?.string, let client = requestValue["client"]?.string, let back = requestValue["return"]?.string,
              let can = requestValue["can"]?.array?.compactMap(\.string), let days = requestValue["days"]?.int else { throw Failed(description: "request") }
        let request = try PKIDelegation.request(for: browser.bundle, can: can, days: days, label: requestValue["label"]?.string ?? "",
                                                nonce: nonce, client: client, returnAddress: back)
        try need(request.json == requestValue, "Swift builds the same request as sso.js for the same inputs")
        let today = try field(f, "today")
        let accepted = try PKIDelegation.accept(try field(f, "answer"), asked: request, key: browser.bundle, issuerBundle: person.bundle, today: today)
        try need(accepted.checked.issuer == person.bundle.signingFingerprint && accepted.checked.to == browser.bundle.signingFingerprint, "the delegation is from the person to the browser key")
        try need(accepted.checked.id == (try field(f, "delegation_id")), "the delegation id is delegation.js's")
        try need(!accepted.checked.issuerIsPinnedRoot, "a fixture person is not the pinned root")
        try need(accepted.delegation == (try PKIJSON(parsing: Data(try field(f, "delegation").utf8))), "the delegation in the answer is the one made")
        func refused(_ what: String, _ body: () throws -> Void) throws {
            do { try body() } catch is PKIDelegation.Failure { return }
            throw Failed(description: "should have been refused: \(what)")
        }
        try refused("an answer to another request") {
            var other = request
            other.nonce = PKIDelegation.newNonce()
            _ = try PKIDelegation.accept(try field(f, "answer"), asked: other, key: browser.bundle, issuerBundle: person.bundle, today: today)
        }
        try refused("a delegation for another key") {
            _ = try PKIDelegation.accept(try field(f, "answer"), asked: request, key: person.bundle, issuerBundle: person.bundle, today: today)
        }
        try refused("a delegation past its date") {
            _ = try PKIDelegation.accept(try field(f, "answer"), asked: request, key: browser.bundle, issuerBundle: person.bundle, today: "2030-01-01")
        }
        try refused("a delegation for another site") {
            _ = try PKIDelegation.check(accepted.delegation, issuerBundle: person.bundle, audience: "https://example.org", today: today)
        }
        try refused("a delegation checked against another key") {
            _ = try PKIDelegation.check(accepted.delegation, issuerBundle: browser.bundle, today: today)
        }
        try refused("a changed delegation") {
            var d = accepted.delegation
            d["until"] = .string("2036-01-01")
            _ = try PKIDelegation.check(d, issuerBundle: person.bundle, today: today)
        }
        try refused("a refusal") {
            _ = try PKIDelegation.accept(try field(f, "denied"), asked: request, key: browser.bundle, issuerBundle: person.bundle, today: today)
        }
        try need(try PKIDelegation.answer(in: try field(f, "denied")) == .denied(nonce: nonce), "a refusal reads as a refusal")
        done.append("the sign-in: Swift's request is sso.js's; delegation.js's delegation checks; seven wrong ones are refused")
        return done
    }
}
