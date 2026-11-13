import CommonCrypto
import CryptoKit
import Foundation

/// The sgit vault primitives, byte-compatible with sgit-ai 0.27 `Vault__Crypto`.
///
/// - file ids: HMAC-SHA256(read key, "<domain>:<vault id>"), first 12 hex
/// - structure key: HKDF-SHA256(read key, no salt, info "sg-vault-v1:structure-key")
/// - objects: iv(12) + AES-256-GCM ciphertext + tag(16)
/// - deflated blobs: "\0sgz1" + iv(12) + AES-256-GCM(zlib(plaintext))
/// - object ids: "obj-cas-imm-" + sha256(ciphertext) hex, 12 (format 1) or 32 (format 2) characters
/// - vault key → read key: PBKDF2-HMAC-SHA256, 600,000 rounds, salt "sg-vault-v1:<vault id>"
/// - vault key → write key: the same, salt "sg-vault-v1:write:<vault id>"
public enum VaultCrypto {
    public static let pbkdf2Rounds: UInt32 = 600_000
    public static let deflateMagic = Data([0x00, 0x73, 0x67, 0x7A, 0x31])   // "\0sgz1"
    public static let ivBytes = 12
    public static let tagBytes = 16

    public static let refDomain = "sg-vault-v1:file-id:ref"
    public static let branchIndexDomain = "sg-vault-v1:file-id:branch-index"
    public static let branchRefDomain = "sg-vault-v1:file-id:branch-ref"
    public static let structureKeyInfo = "sg-vault-v1:structure-key"
    public static let objectPrefix = "obj-cas-imm-"

    // MARK: Key derivation

    /// PBKDF2-HMAC-SHA256 with CommonCrypto.
    public static func pbkdf2(passphrase: String, salt: String, rounds: UInt32 = pbkdf2Rounds) -> SymmetricKey {
        let password = Array(passphrase.utf8)
        let passwordBytes = password.isEmpty ? [UInt8(0)] : password      // a valid pointer even when empty
        let saltBytes = Array(salt.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBufferPointer { pw in
            saltBytes.withUnsafeBufferPointer { st in
                derived.withUnsafeMutableBufferPointer { out in
                    pw.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pw.count) { pwChars in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            pwChars, password.count,
                            st.baseAddress, st.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            rounds,
                            out.baseAddress, out.count)
                    }
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed with status \(status)")
        let key = SymmetricKey(data: derived)
        derived.withUnsafeMutableBufferPointer { buf in
            for i in buf.indices { buf[i] = 0 }
        }
        return key
    }

    public static func deriveReadKey(passphrase: String, vaultId: String) -> SymmetricKey {
        pbkdf2(passphrase: passphrase, salt: "sg-vault-v1:\(vaultId)")
    }

    public static func deriveWriteKey(passphrase: String, vaultId: String) -> SymmetricKey {
        pbkdf2(passphrase: passphrase, salt: "sg-vault-v1:write:\(vaultId)")
    }

    public static func structureKey(readKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: readKey,
                               info: Data(structureKeyInfo.utf8),
                               outputByteCount: 32)
    }

    // MARK: File ids

    public static func fileIdTail(readKey: SymmetricKey, domain: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(domain.utf8), using: readKey)
        return String(Data(mac).hexString.prefix(12))
    }

    public static func branchIndexFileId(readKey: SymmetricKey, vaultId: String) -> String {
        "idx-pid-muw-" + fileIdTail(readKey: readKey, domain: "\(branchIndexDomain):\(vaultId)")
    }

    /// The vault's default ref (the head of the named branch `current` on vaults sgit created).
    public static func refFileId(readKey: SymmetricKey, vaultId: String) -> String {
        "ref-pid-muw-" + fileIdTail(readKey: readKey, domain: "\(refDomain):\(vaultId)")
    }

    // MARK: Object ids

    /// 12 or 32 for a well-formed object id, else 0.
    public static func objectIdWidth(_ objectId: String) -> Int {
        guard objectId.hasPrefix(objectPrefix) else { return 0 }
        let tail = objectId.dropFirst(objectPrefix.count)
        guard tail.count == 12 || tail.count == 32, tail.allSatisfy(\.isHexDigit) else { return 0 }
        return tail.count
    }

    public static func objectId(of ciphertext: Data, width: Int = 12) -> String {
        objectPrefix + String(Data(SHA256.hash(data: ciphertext)).hexString.prefix(width))
    }

    /// True when the ciphertext hashes to the id, at the id's own width.
    public static func objectIdMatches(_ objectId: String, ciphertext: Data) -> Bool {
        let width = objectIdWidth(objectId)
        return width > 0 && self.objectId(of: ciphertext, width: width) == objectId
    }

    // MARK: Encryption

    public enum Envelope: String, Sendable { case gcm = "AES-256-GCM", deflated = "AES-256-GCM + deflate" }

    public struct Opened: Sendable {
        public let plaintext: Data
        public let envelope: Envelope
        public let usedStructureKey: Bool
    }

    /// Decrypt with the read key, then the structure key, reading either envelope.
    public static func open(_ data: Data, readKey: SymmetricKey, structureKey: SymmetricKey?) throws -> Opened {
        let keys: [(SymmetricKey, Bool)] = [(readKey, false)] + (structureKey.map { [($0, true)] } ?? [])
        var inflateError = false
        for (key, isStructure) in keys {
            if data.count > deflateMagic.count + ivBytes + tagBytes,
               data.prefix(deflateMagic.count) == deflateMagic,
               let packed = try? gcmOpen(data.dropFirst(deflateMagic.count), key: key) {
                guard let plain = Zlib.decompress(packed) else { inflateError = true; continue }
                return Opened(plaintext: plain, envelope: .deflated, usedStructureKey: isStructure)
            }
            if let plain = try? gcmOpen(data, key: key) {
                return Opened(plaintext: plain, envelope: .gcm, usedStructureKey: isStructure)
            }
        }
        if inflateError { throw VaultError.inflateFailed(path: "") }
        throw VaultError.decryptFailed(path: "")
    }

    static func gcmOpen<D: DataProtocol>(_ data: D, key: SymmetricKey) throws -> Data {
        let bytes = Data(data)
        guard bytes.count >= ivBytes + tagBytes else { throw VaultError.decryptFailed(path: "") }
        let box = try AES.GCM.SealedBox(combined: bytes)
        return try AES.GCM.open(box, using: key)
    }

    /// iv + AES-256-GCM(plaintext). With `iv` nil a random nonce is used.
    public static func seal(_ plaintext: Data, key: SymmetricKey, iv: Data? = nil) throws -> Data {
        let nonce = try iv.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = box.combined else { throw VaultError.decryptFailed(path: "seal") }
        return combined
    }

    /// sgit's deterministic encryption (trees and tree metadata): iv = HMAC-SHA256(key, plaintext)[:12].
    public static func sealDeterministic(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: plaintext, using: key)
        return try seal(plaintext, key: key, iv: Data(mac).prefix(ivBytes))
    }

    /// Decrypt base64(iv + GCM(utf-8 text)), as tree names and commit messages are stored.
    public static func openMetadata(_ base64: String, readKey: SymmetricKey, structureKey: SymmetricKey?) throws -> String {
        guard let data = Data(base64Encoded: base64) else {
            throw VaultError.malformed(path: "metadata", detail: "not base64")
        }
        let opened = try open(data, readKey: readKey, structureKey: structureKey)
        guard let text = String(data: opened.plaintext, encoding: .utf8) else {
            throw VaultError.malformed(path: "metadata", detail: "not UTF-8")
        }
        return text
    }

    /// sha256(plaintext) hex, first 12: the content hash sgit stores in tree entries.
    public static func contentHash(_ plaintext: Data) -> String {
        String(Data(SHA256.hash(data: plaintext)).hexString.prefix(12))
    }
}

extension Data {
    public var hexString: String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(count * 2)
        for byte in self {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    public init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func value(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: c - 48
            case 97...102: c - 87
            case 65...70: c - 55
            default: nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let hi = value(chars[i]), let lo = value(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        self.init(bytes)
    }
}
