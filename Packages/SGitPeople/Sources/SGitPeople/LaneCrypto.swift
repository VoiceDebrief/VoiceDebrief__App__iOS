// Copied from PrompTugal__App__iOS, Packages/PTLanes/Sources/PTLanes/LaneCrypto.swift, at bf76d29
// (release v0.4.103), on 13 November 2026. Changed here: the PTCore import removed. Moved from
// Apps/VoiceDebrief/Sources/Engine/ into the SGitPeople package on 14 November 2026 and made public.
import CryptoKit
import Foundation
import Security

/// sgit's hybrid envelope (`sgit pki encrypt`, v2), as sgit-ai 0.27 `crypto/PKI__Crypto.py` writes it:
/// a fresh AES-256-GCM key encrypts the message (12-byte IV, ciphertext with its 16-byte tag), RSA-OAEP with
/// SHA-256 (and MGF1-SHA-256) wraps that key to the recipient, and the result is base64 of
/// `{"v": 2, "w": <wrapped key>, "i": <iv>, "c": <ciphertext>}` with each field base64.
/// An append lane stores base64 of that text again ("encoded twice", sgit.ai /api/append-lanes).
public enum LaneCrypto {
    public enum Failure: Error, Equatable, LocalizedError {
        case badPEM, notRSA, keyImport(String), encrypt(String), decrypt(String), badEnvelope, fingerprintMismatch
        public var errorDescription: String? {
            switch self {
            case .badPEM: "The public key is not a PEM block."
            case .notRSA: "The public key is not an RSA key."
            case .keyImport(let why): "The key could not be read (\(why))."
            case .encrypt(let why): "Encryption failed (\(why))."
            case .decrypt(let why): "Decryption failed (\(why))."
            case .badEnvelope: "This is not an sgit envelope."
            case .fingerprintMismatch: "The key's fingerprint does not match the one published with it."
            }
        }
    }

    // MARK: Keys

    /// DER bytes of a `-----BEGIN PUBLIC KEY-----` (SubjectPublicKeyInfo) block.
    public static func der(fromPEM pem: String) throws -> Data {
        let body = pem.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard pem.contains("-----BEGIN"), let der = Data(base64Encoded: body), !der.isEmpty else { throw Failure.badPEM }
        return der
    }

    /// `sha256:` and the first 16 hex characters of SHA-256 over the SPKI DER (sgit's `compute_fingerprint`).
    public static func fingerprint(spki: Data) -> String {
        "sha256:" + SHA256.hash(data: spki).map { String(format: "%02x", $0) }.joined().prefix(16)
    }

    /// The RSAPublicKey (PKCS#1) inside an RSA SubjectPublicKeyInfo, which is what `SecKeyCreateWithData` takes.
    public static func pkcs1(fromSPKI spki: Data) throws -> Data {
        var reader = DERReader(Array(spki))
        var outer = try reader.read(tag: 0x30)                  // SubjectPublicKeyInfo
        var algorithm = try outer.read(tag: 0x30)               // AlgorithmIdentifier
        let oid = try algorithm.read(tag: 0x06)
        guard oid.bytes == [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01] else { throw Failure.notRSA }
        let bits = try outer.read(tag: 0x03)                    // BIT STRING: 0 unused bits, then RSAPublicKey
        guard bits.bytes.first == 0 else { throw Failure.keyImport("unused bits") }
        return Data(bits.bytes.dropFirst())
    }

    /// SubjectPublicKeyInfo for an RSA PKCS#1 public key (what `SecKeyCopyExternalRepresentation` gives).
    public static func spki(fromPKCS1 pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bitString = DERReader.encode(tag: 0x03, [0x00] + Array(pkcs1))
        return Data(DERReader.encode(tag: 0x30, algorithm + bitString))
    }

    public static func pem(spki: Data) -> String {
        let lines = spki.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(lines)\n-----END PUBLIC KEY-----\n"
    }

    public static func publicKey(pem: String) throws -> SecKey {
        let pkcs1 = try pkcs1(fromSPKI: der(fromPEM: pem))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw Failure.keyImport(error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown")
        }
        return key
    }

    /// An RSA private key from PKCS#8 bytes (WebCrypto's `exportKey('pkcs8')`, as the newsroom inbox keeps it).
    public static func privateKey(pkcs8: Data) throws -> SecKey {
        var reader = DERReader(Array(pkcs8))
        var outer = try reader.read(tag: 0x30)                  // PrivateKeyInfo
        _ = try outer.read(tag: 0x02)                           // version
        var algorithm = try outer.read(tag: 0x30)
        guard try algorithm.read(tag: 0x06).bytes == [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01] else { throw Failure.notRSA }
        let pkcs1 = try outer.read(tag: 0x04)                   // OCTET STRING: RSAPrivateKey
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(pkcs1.bytes) as CFData, attributes as CFDictionary, &error) else {
            throw Failure.keyImport(error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown")
        }
        return key
    }

    // MARK: Envelope

    public struct Envelope: Codable, Equatable {
        public let v: Int
        public let w: String
        public let i: String
        public let c: String
        public var f: String?
        public var s: String?

        public init(v: Int, w: String, i: String, c: String, f: String? = nil, s: String? = nil) {
            self.v = v
            self.w = w
            self.i = i
            self.c = c
            self.f = f
            self.s = s
        }
    }

    /// The `.enc` text: base64 of the JSON envelope.
    public static func encrypt(_ plaintext: Data, to recipient: SecKey) throws -> String {
        let contentKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox
        do { sealed = try AES.GCM.seal(plaintext, using: contentKey, nonce: nonce) } catch { throw Failure.encrypt("AES-GCM") }
        let rawKey = contentKey.withUnsafeBytes { Data($0) }
        var error: Unmanaged<CFError>?
        guard SecKeyIsAlgorithmSupported(recipient, .encrypt, .rsaEncryptionOAEPSHA256),
              let wrapped = SecKeyCreateEncryptedData(recipient, .rsaEncryptionOAEPSHA256, rawKey as CFData, &error) as Data? else {
            throw Failure.encrypt(error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "RSA-OAEP not supported")
        }
        // Same field order and separators as Python's json.dumps, so the bytes look like sgit's own.
        let json = "{\"v\": 2, \"w\": \"\(wrapped.base64EncodedString())\", \"i\": \"\(Data(nonce).base64EncodedString())\", \"c\": \"\(Data(sealed.ciphertext + sealed.tag).base64EncodedString())\"}"
        return Data(json.utf8).base64EncodedString()
    }

    /// Decrypts an `.enc` text with the recipient's private key.
    public static func decrypt(_ encText: String, with privateKey: SecKey) throws -> Data {
        guard let json = Data(base64Encoded: encText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: json),
              envelope.v == 1 || envelope.v == 2,
              let wrapped = Data(base64Encoded: envelope.w), let iv = Data(base64Encoded: envelope.i),
              let box = Data(base64Encoded: envelope.c), box.count >= 16 else { throw Failure.badEnvelope }
        var error: Unmanaged<CFError>?
        guard let rawKey = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionOAEPSHA256, wrapped as CFData, &error) as Data? else {
            throw Failure.decrypt(error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "RSA")
        }
        do {
            let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: box.dropLast(16), tag: box.suffix(16))
            return try AES.GCM.open(sealed, using: SymmetricKey(data: rawKey))
        } catch {
            throw Failure.decrypt("AES-GCM")
        }
    }

    /// What goes in the lane's `payload`: base64 of the `.enc` text.
    public static func lanePayload(encText: String) -> String {
        Data(encText.utf8).base64EncodedString()
    }

    /// The `.enc` text from a lane's stored content (decode once).
    public static func encText(fromLaneContent content: String) throws -> String {
        guard let data = Data(base64Encoded: content.trimmingCharacters(in: .whitespacesAndNewlines)),
              let text = String(data: data, encoding: .utf8) else { throw Failure.badEnvelope }
        return text
    }
}

/// Just enough DER to unwrap and wrap an RSA public key.
public struct DERReader {
    private var bytes: [UInt8]
    private var index = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public struct Element {
        public let bytes: [UInt8]
        public init(bytes: [UInt8]) { self.bytes = bytes }
        public mutating func read(tag: UInt8) throws -> Element {
            var reader = DERReader(bytes)
            let element = try reader.read(tag: tag)
            self = Element(bytes: Array(bytes[reader.index...]))
            return element
        }
    }

    public mutating func read(tag: UInt8) throws -> Element {
        guard index < bytes.count, bytes[index] == tag else { throw LaneCrypto.Failure.keyImport("DER tag") }
        index += 1
        guard index < bytes.count else { throw LaneCrypto.Failure.keyImport("DER length") }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { throw LaneCrypto.Failure.keyImport("DER length") }
            length = bytes[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        guard index + length <= bytes.count else { throw LaneCrypto.Failure.keyImport("DER truncated") }
        let element = Element(bytes: Array(bytes[index..<(index + length)]))
        index += length
        return element
    }

    public static func encode(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let count = content.count
        let length: [UInt8]
        if count < 0x80 {
            length = [UInt8(count)]
        } else {
            var digits: [UInt8] = []
            var n = count
            while n > 0 { digits.insert(UInt8(n & 0xFF), at: 0); n >>= 8 }
            length = [0x80 | UInt8(digits.count)] + digits
        }
        return [tag] + length + content
    }
}
