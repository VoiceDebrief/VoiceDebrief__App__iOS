import CommonCrypto
import CryptoKit
import Foundation
import Security

/// PKIKit: one sgit-compatible identity, as `sgit pki` (sgit-ai 0.27) and pki.sgit.ai's keys.js make and read it.
///
///   encryption pair   RSA-OAEP 4096, e = 65537, SHA-256
///   signing pair      ECDSA P-256 over SHA-256, signatures raw r‖s (64 bytes)
///   fingerprint       "sha256:" + the first 16 hex of SHA-256 over the DER SubjectPublicKeyInfo
///   public bundle     { v: 1, encrypt, sign, label, fingerprint, signing_fingerprint }, keys as PEM
///   private halves    PKCS#8 bytes; as PEM, encrypted with a passphrase (PBES2: PBKDF2-HMAC-SHA256, AES-256-CBC)
///   key code          k1.<encryption SPKI>.<signing SPKI>.<label>, each base64url
///   detached sig      { "signature": base64 of r‖s, "fingerprint": the signing fingerprint }
///   statements        canonical bytes are key-sorted compact JSON without `sig`, plus a newline; `sig` is base64 of r‖s
///   envelope          sgit's hybrid v2, with `s` (a signature over the ciphertext) and `f` when signed
///
/// Nothing here touches the Keychain: keys come in and go out as bytes. `LaneCrypto.swift` holds the unsigned
/// envelope and the RSA SPKI conversion this builds on. `pki-interop.yml` has sgit and keys.js read what this
/// writes, and this read what they write.
enum PKIError: Error, Equatable, LocalizedError {
    case der(String)
    case key(String)
    case format(String)
    case crypto(String)

    var errorDescription: String? {
        switch self {
        case .der(let why): "The key's encoding does not read (\(why))."
        case .key(let why): "The key could not be used (\(why))."
        case .format(let why): "Not in the expected form (\(why))."
        case .crypto(let why): "The cryptography failed (\(why))."
        }
    }
}

/// The public half of an identity, in the shape `sgit pki export` prints.
struct PKIBundle: Codable, Equatable, Hashable, Sendable {
    var v: Int = 1
    var encrypt: String
    var sign: String
    var label: String
    var fingerprint: String
    var signingFingerprint: String

    enum CodingKeys: String, CodingKey {
        case v, encrypt, sign, label, fingerprint
        case signingFingerprint = "signing_fingerprint"
    }

    /// The text `sgit pki export` writes: `json.dumps(bundle, indent=2)`, in sgit's key order.
    var json: String {
        let fields: [(String, String)] = [
            ("v", String(v)), ("encrypt", PKIJSON.quote(encrypt)), ("sign", PKIJSON.quote(sign)),
            ("label", PKIJSON.quote(label)), ("fingerprint", PKIJSON.quote(fingerprint)),
            ("signing_fingerprint", PKIJSON.quote(signingFingerprint)),
        ]
        return "{\n" + fields.map { "  \"\($0.0)\": \($0.1)" }.joined(separator: ",\n") + "\n}"
    }

    var asJSON: PKIJSON {
        .object(["v": .int(v), "encrypt": .string(encrypt), "sign": .string(sign), "label": .string(label),
                 "fingerprint": .string(fingerprint), "signing_fingerprint": .string(signingFingerprint)])
    }

    init(v: Int = 1, encrypt: String, sign: String, label: String, fingerprint: String, signingFingerprint: String) {
        self.v = v
        self.encrypt = encrypt
        self.sign = sign
        self.label = label
        self.fingerprint = fingerprint
        self.signingFingerprint = signingFingerprint
    }

    init(json value: PKIJSON) throws {
        guard case .int(let v)? = value["v"], case .string(let encrypt)? = value["encrypt"],
              case .string(let sign)? = value["sign"] else { throw PKIError.format("not a public-key bundle") }
        self.v = v
        self.encrypt = encrypt
        self.sign = sign
        self.label = value["label"]?.string ?? ""
        self.fingerprint = value["fingerprint"]?.string ?? ""
        self.signingFingerprint = value["signing_fingerprint"]?.string ?? ""
    }
}

/// An identity with its private halves, as PKCS#8 bytes. Secret.
struct PKIIdentity: Codable, Equatable, Sendable {
    var bundle: PKIBundle
    var encryptPKCS8: Data
    var signPKCS8: Data
    var created: Date
}

/// What opening an envelope gives. `verified` is nil when the signer's bundle was not given: "not checked",
/// which must never be shown as "forged".
struct PKIOpened: Equatable, Sendable {
    var bytes: Data
    var signed: Bool
    var signer: String?
    var verified: Bool?
}

enum PKI {
    static let fingerprintLength = "sha256:".count + 16

    static func isFingerprint(_ text: String) -> Bool {
        guard text.hasPrefix("sha256:"), text.utf8.count == fingerprintLength else { return false }
        return text.dropFirst(7).allSatisfy { $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }
    }

    // MARK: base64url

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url text: String) -> Data? {
        guard text.utf8.allSatisfy({ c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x5F
        }) else { return nil }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.utf8.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    // MARK: PEM

    static func pem(_ der: Data, label: String) -> String {
        let lines = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(lines)\n-----END \(label)-----\n"
    }

    /// The label and DER bytes of the first PEM block in `text`.
    static func unpem(_ text: String) throws -> (label: String, der: Data) {
        guard let begin = text.range(of: "-----BEGIN "),
              let labelEnd = text.range(of: "-----", range: begin.upperBound..<text.endIndex) else { throw PKIError.format("not a PEM block") }
        let label = String(text[begin.upperBound..<labelEnd.lowerBound])
        guard let end = text.range(of: "-----END \(label)-----", range: labelEnd.upperBound..<text.endIndex) else {
            throw PKIError.format("not a PEM block")
        }
        let body = text[labelEnd.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let der = Data(base64Encoded: String(body)), !der.isEmpty else { throw PKIError.format("not a PEM block") }
        return (label, der)
    }

    static func publicDER(_ pem: String) throws -> Data {
        let (label, der) = try unpem(pem)
        guard label == "PUBLIC KEY" else { throw PKIError.format("a \(label.lowercased()) PEM is not a public key") }
        return der
    }

    // MARK: Keys

    static let rsaAlgorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]

    /// PKCS#8 PrivateKeyInfo around an RSAPrivateKey (PKCS#1), which is what the Security framework exports.
    static func rsaPKCS8(fromPKCS1 pkcs1: Data) -> Data {
        let version: [UInt8] = [0x02, 0x01, 0x00]
        return Data(DERReader.encode(tag: 0x30, version + rsaAlgorithm + DERReader.encode(tag: 0x04, Array(pkcs1))))
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown"
    }

    /// The SPKI of the public half of an RSA private key given as PKCS#8.
    static func rsaSPKI(fromPKCS8 pkcs8: Data) throws -> Data {
        let key: SecKey
        do { key = try LaneCrypto.privateKey(pkcs8: pkcs8) } catch { throw PKIError.key("not an RSA private key") }
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(key),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { throw PKIError.key(describe(error)) }
        return LaneCrypto.spki(fromPKCS1: pkcs1)
    }

    static func signingKey(pkcs8: Data) throws -> P256.Signing.PrivateKey {
        do { return try P256.Signing.PrivateKey(derRepresentation: pkcs8) } catch { throw PKIError.key("not a P-256 private key") }
    }

    static func signingPublicKey(spki: Data) throws -> P256.Signing.PublicKey {
        do { return try P256.Signing.PublicKey(derRepresentation: spki) } catch { throw PKIError.key("not a P-256 public key") }
    }

    /// A new identity. RSA-4096 generation takes seconds: call it off the main thread.
    /// `rsaBits` exists for tests, which make smaller keys to stay quick; sgit makes 4096.
    static func generate(label: String, rsaBits: Int = 4096, now: Date = Date()) throws -> PKIIdentity {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeySizeInBits as String: rsaBits]
        var error: Unmanaged<CFError>?
        guard let rsa = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let pkcs1 = SecKeyCopyExternalRepresentation(rsa, &error) as Data? else { throw PKIError.key(describe(error)) }
        let encryptPKCS8 = rsaPKCS8(fromPKCS1: pkcs1)
        let signing = P256.Signing.PrivateKey()
        let signPKCS8 = signing.derRepresentation
        let bundle = bundle(encryptSPKI: try rsaSPKI(fromPKCS8: encryptPKCS8), signSPKI: signing.publicKey.derRepresentation, label: label)
        return PKIIdentity(bundle: bundle, encryptPKCS8: encryptPKCS8, signPKCS8: signPKCS8, created: now)
    }

    static func bundle(encryptSPKI: Data, signSPKI: Data, label: String) -> PKIBundle {
        PKIBundle(encrypt: pem(encryptSPKI, label: "PUBLIC KEY"), sign: pem(signSPKI, label: "PUBLIC KEY"), label: label,
                  fingerprint: LaneCrypto.fingerprint(spki: encryptSPKI), signingFingerprint: LaneCrypto.fingerprint(spki: signSPKI))
    }

    /// The public bundle recomputed from the two private halves, so that an import trusts nothing it was told.
    static func bundle(encryptPKCS8: Data, signPKCS8: Data, label: String) throws -> PKIBundle {
        bundle(encryptSPKI: try rsaSPKI(fromPKCS8: encryptPKCS8),
               signSPKI: try signingKey(pkcs8: signPKCS8).publicKey.derRepresentation, label: label)
    }

    /// What is wrong with a bundle: both keys must be what they claim and both fingerprints theirs. Empty when sound.
    static func problems(of bundle: PKIBundle) -> [String] {
        guard bundle.v == 1 else { return ["not a v1 public-key bundle"] }
        var out: [String] = []
        var bits = 0
        do {
            let key = try LaneCrypto.publicKey(pem: bundle.encrypt)
            bits = SecKeyGetBlockSize(key) * 8
        } catch { out.append("the encryption key is not an RSA public key") }
        do { _ = try signingPublicKey(spki: try publicDER(bundle.sign)) } catch { out.append("the signing key is not an ECDSA P-256 public key") }
        guard out.isEmpty, let encrypt = try? publicDER(bundle.encrypt), let sign = try? publicDER(bundle.sign) else { return out }
        if LaneCrypto.fingerprint(spki: encrypt) != bundle.fingerprint { out.append("fingerprint is not the encryption key's") }
        if LaneCrypto.fingerprint(spki: sign) != bundle.signingFingerprint { out.append("signing_fingerprint is not the signing key's") }
        if bits < 3072 { out.append("the encryption key is \(bits)-bit; sgit makes 4096") }
        return out
    }

    // MARK: The k1 key code

    /// `k1.<encryption SPKI>.<signing SPKI>.<label>`: a public key as text, for a link or a QR code.
    static func keyCode(_ bundle: PKIBundle) throws -> String {
        "k1.\(base64url(try publicDER(bundle.encrypt))).\(base64url(try publicDER(bundle.sign))).\(base64url(Data(bundle.label.utf8)))"
    }

    /// The bundle a k1 code carries, recomputed from its two keys. Nil when `text` holds no code.
    /// Length limits are keys.js's (`parseKeyCode`).
    static func parseKeyCode(_ text: String) -> PKIBundle? {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        var search = text.startIndex
        while let start = text.range(of: "k1.", range: search..<text.endIndex) {
            search = start.upperBound
            var parts: [String] = [""]
            for c in text[start.upperBound...].utf8 {
                if c == 0x2E {
                    if parts.count == 3 { break }
                    parts.append("")
                } else if allowed.contains(c) {
                    parts[parts.count - 1].unicodeScalars.append(Unicode.Scalar(c))
                } else { break }
            }
            guard parts.count == 3, (100...1200).contains(parts[0].utf8.count), (60...200).contains(parts[1].utf8.count),
                  parts[2].utf8.count <= 200, let encrypt = data(base64url: parts[0]), let sign = data(base64url: parts[1]),
                  let labelBytes = data(base64url: parts[2]), let label = String(data: labelBytes, encoding: .utf8) else { continue }
            let made = bundle(encryptSPKI: encrypt, signSPKI: sign, label: label)
            if problems(of: made).allSatisfy({ $0.contains("-bit") }) { return made }
        }
        return nil
    }

    // MARK: Signatures

    /// Raw r‖s (64 bytes) over `data`, hashed with SHA-256.
    static func sign(_ data: Data, signPKCS8: Data) throws -> Data {
        do { return try signingKey(pkcs8: signPKCS8).signature(for: data).rawRepresentation } catch let e as PKIError { throw e } catch {
            throw PKIError.crypto("signing")
        }
    }

    static func verify(signature: Data, over data: Data, signSPKI: Data) -> Bool {
        guard signature.count == 64, let key = try? signingPublicKey(spki: signSPKI),
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        return key.isValidSignature(parsed, for: data)
    }

    static func verify(signature: Data, over data: Data, signPEM: String) -> Bool {
        guard let spki = try? publicDER(signPEM) else { return false }
        return verify(signature: signature, over: data, signSPKI: spki)
    }

    /// The `.sig` file `sgit pki sign` writes beside a file.
    static func detachedSignature(over data: Data, by identity: PKIIdentity) throws -> String {
        let signature = try sign(data, signPKCS8: identity.signPKCS8)
        return "{\n  \"signature\": \(PKIJSON.quote(signature.base64EncodedString())),\n  \"fingerprint\": \(PKIJSON.quote(identity.bundle.signingFingerprint))\n}"
    }

    /// True only when the `.sig` names this bundle's signing key and the signature is that key's over `data`.
    static func verifyDetached(_ sigJSON: String, over data: Data, by bundle: PKIBundle) -> Bool {
        guard let value = try? PKIJSON(parsing: Data(sigJSON.utf8)), let fingerprint = value["fingerprint"]?.string,
              let text = value["signature"]?.string, let signature = Data(base64Encoded: text),
              fingerprint == bundle.signingFingerprint else { return false }
        return verify(signature: signature, over: data, signPEM: bundle.sign)
    }

    // MARK: Statements

    /// What a statement's signature covers: the statement without `sig`, canonical, plus the newline jq ends with.
    static func canonicalBytes(_ statement: PKIJSON) -> Data {
        var rest = statement
        rest["sig"] = nil
        return Data((rest.canonical + "\n").utf8)
    }

    /// `sha256:` and SHA-256 over the canonical form of the whole statement, `sig` included.
    static func statementId(_ statement: PKIJSON) -> String {
        "sha256:" + SHA256.hash(data: Data((statement.canonical + "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Signs with whatever holds the key: `signer` returns raw r‖s over the bytes it is given.
    static func signStatement(_ statement: PKIJSON, with signer: (Data) throws -> Data) throws -> PKIJSON {
        var out = statement
        out["sig"] = nil
        out["sig"] = .string(try signer(canonicalBytes(out)).base64EncodedString())
        return out
    }

    static func signStatement(_ statement: PKIJSON, signPKCS8: Data) throws -> PKIJSON {
        try signStatement(statement) { try sign($0, signPKCS8: signPKCS8) }
    }

    static func verifyStatement(_ statement: PKIJSON, signPEM: String) -> Bool {
        guard let text = statement["sig"]?.string, let signature = Data(base64Encoded: text) else { return false }
        return verify(signature: signature, over: canonicalBytes(statement), signPEM: signPEM)
    }

    // MARK: The envelope

    /// Seals `plaintext` to a bundle's encryption key. With a signer it carries `s` and `f` as
    /// `sgit pki encrypt --fingerprint` writes them: a signature over the ciphertext, and the signing fingerprint.
    static func seal(_ plaintext: Data, to recipient: PKIBundle, signedBy signer: PKIIdentity? = nil) throws -> String {
        let key: SecKey
        do { key = try LaneCrypto.publicKey(pem: recipient.encrypt) } catch { throw PKIError.key("the recipient's encryption key does not read") }
        let contentKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        guard let sealed = try? AES.GCM.seal(plaintext, using: contentKey, nonce: nonce) else { throw PKIError.crypto("AES-GCM") }
        let ciphertext = Data(sealed.ciphertext + sealed.tag)
        let rawKey = contentKey.withUnsafeBytes { Data($0) }
        var error: Unmanaged<CFError>?
        guard let wrapped = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256, rawKey as CFData, &error) as Data? else {
            throw PKIError.crypto(describe(error))
        }
        var json = "{\"v\": 2, \"w\": \"\(wrapped.base64EncodedString())\", \"i\": \"\(Data(nonce).base64EncodedString())\", \"c\": \"\(ciphertext.base64EncodedString())\""
        if let signer {
            let signature = try sign(ciphertext, signPKCS8: signer.signPKCS8)
            json += ", \"s\": \"\(signature.base64EncodedString())\", \"f\": \(PKIJSON.quote(signer.bundle.signingFingerprint))"
        }
        return Data((json + "}").utf8).base64EncodedString()
    }

    /// Opens an envelope with a private encryption key (PKCS#8). The signature is checked only against a
    /// bundle in `signers` whose signing fingerprint the envelope names.
    static func unseal(_ encText: String, encryptPKCS8: Data, signers: [PKIBundle] = []) throws -> PKIOpened {
        guard let json = Data(base64Encoded: encText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let envelope = try? JSONDecoder().decode(LaneCrypto.Envelope.self, from: json) else { throw PKIError.format("not an sgit envelope") }
        let key: SecKey
        do { key = try LaneCrypto.privateKey(pkcs8: encryptPKCS8) } catch { throw PKIError.key("not an RSA private key") }
        let bytes: Data
        do { bytes = try LaneCrypto.decrypt(encText, with: key) } catch { throw PKIError.crypto("not sealed to this key, or changed on the way") }
        var opened = PKIOpened(bytes: bytes, signed: false, signer: nil, verified: nil)
        if let s = envelope.s, let f = envelope.f, !s.isEmpty, !f.isEmpty {
            opened.signed = true
            opened.signer = f
            if let bundle = signers.first(where: { $0.signingFingerprint == f }),
               let signature = Data(base64Encoded: s), let ciphertext = Data(base64Encoded: envelope.c) {
                opened.verified = verify(signature: signature, over: ciphertext, signPEM: bundle.sign)
            }
        }
        return opened
    }

    // MARK: Private keys protected by a passphrase (PBES2)

    private static let oidPBES2: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0D]
    private static let oidPBKDF2: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C]
    private static let oidHMACSHA256: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x09]
    private static let oidHMACSHA1: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x07]
    private static let oidAES256CBC: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2A]
    private static let oidAES128CBC: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x02]

    private static func pbkdf2(_ passphrase: String, salt: [UInt8], iterations: Int, sha256: Bool, length: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: length)
        let password = Array(passphrase.utf8)
        let status = password.withUnsafeBufferPointer { p -> Int32 in
            p.withMemoryRebound(to: CChar.self) { chars in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), chars.baseAddress, password.count, salt, salt.count,
                                     CCPseudoRandomAlgorithm(sha256 ? kCCPRFHmacAlgSHA256 : kCCPRFHmacAlgSHA1),
                                     UInt32(iterations), &out, length)
            }
        }
        guard Int(status) == kCCSuccess else { throw PKIError.crypto("PBKDF2") }
        return out
    }

    private static func aesCBC(_ operation: Int, key: [UInt8], iv: [UInt8], _ input: [UInt8]) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let capacity = out.count
        var moved = 0
        let status = CCCrypt(CCOperation(operation), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &out, capacity, &moved)
        guard Int(status) == kCCSuccess else { throw PKIError.crypto("wrong passphrase, or not this key") }
        return Array(out.prefix(moved))
    }

    private static func derInteger(_ value: Int) -> [UInt8] {
        var digits: [UInt8] = []
        var n = value
        repeat { digits.insert(UInt8(n & 0xFF), at: 0); n >>= 8 } while n > 0
        if digits[0] & 0x80 != 0 { digits.insert(0, at: 0) }
        return DERReader.encode(tag: 0x02, digits)
    }

    /// A PKCS#8 private key as an `ENCRYPTED PRIVATE KEY` PEM: PBES2 with PBKDF2-HMAC-SHA256 and AES-256-CBC,
    /// the form python-cryptography writes for sgit's key store and reads back.
    static func encryptPrivate(_ pkcs8: Data, passphrase: String, iterations: Int = 210_000) throws -> String {
        guard !passphrase.isEmpty else { throw PKIError.format("a passphrase is required: sgit keeps private keys encrypted at rest") }
        let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let iv = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let key = try pbkdf2(passphrase, salt: salt, iterations: iterations, sha256: true, length: 32)
        let ciphertext = try aesCBC(kCCEncrypt, key: key, iv: iv, Array(pkcs8))
        let seq = { (parts: [UInt8]) in DERReader.encode(tag: 0x30, parts) }
        let oid = { (bytes: [UInt8]) in DERReader.encode(tag: 0x06, bytes) }
        let octets = { (bytes: [UInt8]) in DERReader.encode(tag: 0x04, bytes) }
        let kdf = seq(oid(oidPBKDF2) + seq(octets(salt) + derInteger(iterations) + seq(oid(oidHMACSHA256) + [0x05, 0x00])))
        let cipher = seq(oid(oidAES256CBC) + octets(iv))
        let algorithm = seq(oid(oidPBES2) + seq(kdf + cipher))
        return pem(Data(seq(algorithm + octets(ciphertext))), label: "ENCRYPTED PRIVATE KEY")
    }

    /// PKCS#8 bytes from a `PRIVATE KEY` PEM, or from an `ENCRYPTED PRIVATE KEY` PEM and its passphrase.
    static func decryptPrivate(_ text: String, passphrase: String) throws -> Data {
        let (label, der) = try unpem(text)
        if label == "PRIVATE KEY" { return der }
        guard label == "ENCRYPTED PRIVATE KEY" else { throw PKIError.format("a \(label.lowercased()) PEM is not a PKCS#8 private key") }
        let outer = try PKIDER.one(Array(der)).children()
        guard outer.count == 2, outer[0].tag == 0x30, outer[1].tag == 0x04 else { throw PKIError.der("EncryptedPrivateKeyInfo") }
        let algorithm = try outer[0].children()
        guard algorithm.count == 2, algorithm[0].content == oidPBES2 else { throw PKIError.format("only PBES2-encrypted keys are read here (sgit writes PBES2)") }
        let schemes = try algorithm[1].children()
        guard schemes.count == 2 else { throw PKIError.der("PBES2 parameters") }
        let kdf = try schemes[0].children()
        guard kdf.count == 2, kdf[0].content == oidPBKDF2 else { throw PKIError.format("only PBKDF2 is read here") }
        let kdfParameters = try kdf[1].children()
        guard kdfParameters.count >= 2, kdfParameters[0].tag == 0x04, kdfParameters[1].tag == 0x02,
              kdfParameters[1].content.count <= 4 else { throw PKIError.der("PBKDF2 parameters") }
        let salt = kdfParameters[0].content
        let iterations = kdfParameters[1].content.reduce(0) { $0 << 8 | Int($1) }
        guard iterations > 0, iterations <= 10_000_000 else { throw PKIError.der("PBKDF2 iterations") }
        var sha256 = false                                      // the default PRF is HMAC-SHA1
        if let prf = kdfParameters.first(where: { $0.tag == 0x30 }) {
            let id = try prf.children().first?.content
            if id == oidHMACSHA256 { sha256 = true } else if id != oidHMACSHA1 { throw PKIError.format("unknown PBKDF2 hash") }
        }
        let cipher = try schemes[1].children()
        guard cipher.count == 2, cipher[1].tag == 0x04, cipher[1].content.count == 16 else { throw PKIError.der("cipher parameters") }
        let length: Int
        if cipher[0].content == oidAES256CBC { length = 32 } else if cipher[0].content == oidAES128CBC { length = 16 } else {
            throw PKIError.format("only AES-CBC-encrypted keys are read here")
        }
        let key = try pbkdf2(passphrase, salt: salt, iterations: iterations, sha256: sha256, length: length)
        let plain = try aesCBC(kCCDecrypt, key: key, iv: cipher[1].content, outer[1].content)
        // A wrong passphrase usually fails the padding; when it does not, what comes out is not a key.
        guard plain.first == 0x30, (try? PKIDER.one(plain)) != nil else { throw PKIError.crypto("wrong passphrase, or not this key") }
        return Data(plain)
    }

    /// The five files of one key in sgit's key store (`~/.sg-send/keys/sha256_<encryption fingerprint>/`),
    /// private halves encrypted with the passphrase.
    static func keystoreFiles(_ identity: PKIIdentity, passphrase: String) throws -> (folder: String, files: [String: String]) {
        let b = identity.bundle
        let metadata = "{\n  \"label\": \(PKIJSON.quote(b.label)),\n  \"algorithm\": \"RSA-OAEP\",\n  \"key_size\": 4096,\n  \"encryption_fingerprint\": \(PKIJSON.quote(b.fingerprint)),\n  \"signing_fingerprint\": \(PKIJSON.quote(b.signingFingerprint)),\n  \"created\": \(Int(identity.created.timeIntervalSince1970 * 1000))\n}"
        return (b.fingerprint.replacingOccurrences(of: ":", with: "_"), [
            "metadata.json": metadata,
            "private_key.pem": try encryptPrivate(identity.encryptPKCS8, passphrase: passphrase),
            "public_key.pem": b.encrypt,
            "signing_private.pem": try encryptPrivate(identity.signPKCS8, passphrase: passphrase),
            "signing_public.pem": b.sign,
        ])
    }

    /// An identity from sgit's two private PEMs and their passphrase. The public bundle is recomputed, not trusted.
    static func importKeystore(privateKeyPEM: String, signingPrivatePEM: String, passphrase: String, label: String,
                               created: Date = Date()) throws -> PKIIdentity {
        let encrypt = try decryptPrivate(privateKeyPEM, passphrase: passphrase)
        let sign = try decryptPrivate(signingPrivatePEM, passphrase: passphrase)
        return PKIIdentity(bundle: try bundle(encryptPKCS8: encrypt, signPKCS8: sign, label: label),
                           encryptPKCS8: encrypt, signPKCS8: sign, created: created)
    }
}

/// DER read as a tree, as much as PKCS#8 and PBES2 need. Definite lengths only; every length is checked
/// against the bytes that are there.
struct PKIDER: Equatable {
    let tag: UInt8
    let content: [UInt8]

    /// One element that fills `bytes` exactly.
    static func one(_ bytes: [UInt8]) throws -> PKIDER {
        let (node, used) = try read(bytes, at: 0)
        guard used == bytes.count else { throw PKIError.der("bytes after the end") }
        return node
    }

    static func read(_ bytes: [UInt8], at start: Int) throws -> (PKIDER, next: Int) {
        guard start >= 0, start + 2 <= bytes.count else { throw PKIError.der("truncated") }
        let tag = bytes[start]
        guard tag & 0x1F != 0x1F else { throw PKIError.der("long tags are not read here") }
        var index = start + 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { throw PKIError.der("length") }
            length = bytes[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        guard length >= 0, index + length <= bytes.count else { throw PKIError.der("truncated") }
        return (PKIDER(tag: tag, content: Array(bytes[index..<(index + length)])), index + length)
    }

    /// The elements inside a constructed one (a SEQUENCE, say).
    func children() throws -> [PKIDER] {
        guard tag & 0x20 != 0 else { throw PKIError.der("not a constructed element") }
        var out: [PKIDER] = []
        var index = 0
        while index < content.count {
            let (node, next) = try PKIDER.read(content, at: index)
            out.append(node)
            index = next
        }
        return out
    }
}

/// JSON as statements carry it: no non-integer numbers (registry/params.json at pki.sgit.ai). Its canonical
/// text is keys.js's `canon`, which is `jq -cS`: keys sorted, no spaces, strings as JavaScript writes them.
enum PKIJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([PKIJSON])
    case object([String: PKIJSON])

    init(parsing data: Data) throws {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw PKIError.format("not JSON") }
        self = try PKIJSON(any: any)
    }

    private init(any: Any) throws {
        switch any {
        case is NSNull: self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue); return }
            let double = number.doubleValue
            guard double == double.rounded(), abs(double) < 9_007_199_254_740_992 else { throw PKIError.format("statements carry no non-integer numbers") }
            self = .int(number.intValue)
        case let text as String: self = .string(text)
        case let list as [Any]: self = .array(try list.map { try PKIJSON(any: $0) })
        case let dict as [String: Any]: self = .object(try dict.mapValues { try PKIJSON(any: $0) })
        default: throw PKIError.format("not JSON")
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? { if case .int(let n) = self { return n }; return nil }
    var array: [PKIJSON]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: PKIJSON]? { if case .object(let o) = self { return o }; return nil }

    subscript(key: String) -> PKIJSON? {
        get { object?[key] }
        set {
            guard case .object(var fields) = self else { return }
            fields[key] = newValue
            self = .object(fields)
        }
    }

    /// A string as `JSON.stringify` writes it: only the quote, the backslash and control characters escaped.
    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0..<0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Keys in JavaScript's order (`Array.prototype.sort`: by UTF-16 code unit), compact.
    var canonical: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .string(let s): return PKIJSON.quote(s)
        case .array(let items): return "[" + items.map(\.canonical).joined(separator: ",") + "]"
        case .object(let fields):
            let keys = fields.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            return "{" + keys.map { PKIJSON.quote($0) + ":" + (fields[$0] ?? .null).canonical }.joined(separator: ",") + "}"
        }
    }

    var data: Data { Data(canonical.utf8) }
}
