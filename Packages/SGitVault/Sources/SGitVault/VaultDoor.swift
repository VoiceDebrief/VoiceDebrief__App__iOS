import CryptoKit
import Foundation

/// The website's passkey door, ported from https://promptugal.news/assets/vault/door.js (read 7 Nov 2026).
///
///     prf input   = SHA-256("web-summit.newsroom.sgit.ai/door/v1")                  a public constant
///     seed        = HKDF-SHA256(ikm = PRF bytes, salt = SHA-256("web-summit.newsroom.sgit.ai"), info "sgit/door/v1", 32)
///     passphrase  = hex(HKDF-SHA256(seed, no salt, "sgit/door/v1/passphrase", 32))
///     vault id    = 8 of [a-z0-9] from HKDF-SHA256(seed, no salt, "sgit/door/v1/id[/counter][/round]", 64), bytes < 252
///     door key    = sgit_private_vault_<passphrase>:<vault id>
///
/// A recovery code (26 base32 characters, 16 bytes) is used as the ikm in place of the PRF bytes.
/// Changing any constant here locks every existing account out: they are a contract with the website.
public enum VaultDoor {
    /// The site constant from door.js (`RP_FOR_DERIVATION`). Not the passkey's relying party id.
    public static let rpForDerivation = "web-summit.newsroom.sgit.ai"
    public static let prfInputText = "\(rpForDerivation)/door/v1"
    /// The PRF "salt" (WebAuthn `prf.eval.first`) the website passes: SHA-256 of the input text.
    public static var prfSalt: Data { Data(SHA256.hash(data: Data(prfInputText.utf8))) }

    /// The site constant of pki.sgit.ai's door.js: the register of people, and VoiceDebrief's account.
    public static let pkiSite = "pki.sgit.ai"
    /// The PRF "salt" for a door on another site: SHA-256 of "<site>/door/v1".
    public static func prfSalt(site: String) -> Data { Data(SHA256.hash(data: Data("\(site)/door/v1".utf8))) }

    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    static let base32 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public struct Door: Sendable, CustomStringConvertible {
        public let vaultId: String
        let passphrase: String
        public var description: String { "Door(vault \(vaultId))" }
        /// sgit's vault key text for the door vault. Secret.
        public var vaultKeyText: String { "sgit_private_vault_\(passphrase):\(vaultId)" }
    }

    static func hkdf(_ ikm: Data, salt: Data, info: String, count: Int) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt,
                                         info: Data(info.utf8), outputByteCount: count)
        return key.withUnsafeBytes { Data($0) }
    }

    /// From 32 PRF bytes (or the 16 bytes of a recovery code) to the door's vault id and passphrase.
    public static func door(fromSecret ikm: Data, counter: Int = 0) -> Door {
        door(fromSecret: ikm, site: rpForDerivation, counter: counter)
    }

    /// The same derivation for another site's door (door.js differs between sites in this constant only).
    public static func door(fromSecret ikm: Data, site: String, counter: Int = 0) -> Door {
        let rpHash = Data(SHA256.hash(data: Data(site.utf8)))
        let seed = hkdf(ikm, salt: rpHash, info: "sgit/door/v1", count: 32)
        let passphrase = hkdf(seed, salt: Data(), info: "sgit/door/v1/passphrase", count: 32).hexString
        return Door(vaultId: vaultId(seed: seed, counter: counter), passphrase: passphrase)
    }

    static func vaultId(seed: Data, counter: Int) -> String {
        var out = ""
        var round = 0
        while out.count < 8 && round < 8 {
            let info = "sgit/door/v1/id" + (counter != 0 ? "/\(counter)" : "") + (round != 0 ? "/\(round)" : "")
            for byte in hkdf(seed, salt: Data(), info: info, count: 64) {
                if byte < 252 { out.append(alphabet[Int(byte) % 36]) }
                if out.count == 8 { break }
            }
            round += 1
        }
        return out
    }

    /// A recovery code ("ABCD-EFGH-…", 26 base32 characters) to its 16 bytes. Nil if it is not one.
    public static func recoveryBytes(_ code: String) -> Data? {
        let chars = code.uppercased().filter { base32.contains($0) }
        guard chars.count == 26 else { return nil }
        var bits = ""
        for c in chars {
            let v = base32.firstIndex(of: c)!
            let b = String(v, radix: 2)
            bits += String(repeating: "0", count: 5 - b.count) + b
        }
        let bitArray = Array(bits)
        var out = Data()
        for i in 0..<16 {
            out.append(UInt8(String(bitArray[(i * 8)..<(i * 8 + 8)]), radix: 2)!)
        }
        return out
    }

    /// The door vault's key: PBKDF2 twice (600,000 rounds each). Call off the main actor.
    public static func key(for door: Door) -> VaultKey {
        VaultKey(kind: .vault, vaultId: door.vaultId,
                 readKey: VaultCrypto.deriveReadKey(passphrase: door.passphrase, vaultId: door.vaultId),
                 writeKey: VaultCrypto.deriveWriteKey(passphrase: door.passphrase, vaultId: door.vaultId))
    }
}

/// The website's account: door vault → master vault → reader vault (assets/vault/vault-core.js).
public enum VaultAccount {
    public static let doorMasterKeyFile = "master-key.json"
    public static let masterReaderFile = "reader.json"
    public static let masterDoorsFile = "doors.json"
    /// Where the website keeps the access token that allows writes (assets/vault/vault.js TOKEN_FILE).
    public static let masterTokenFile = ".vault/access-token.json"

    public struct Keys: Sendable, CustomStringConvertible {
        public let door: VaultKey
        public let master: VaultKey
        public let reader: VaultKey?
        /// The access token from the master vault, if it holds one. Secret.
        public let accessToken: String?
        public let doorCount: Int
        public var description: String {
            "Account(door \(door.vaultId), master \(master.vaultId), reader \(reader?.vaultId ?? "none"), token: \(accessToken == nil ? "no" : "yes"))"
        }
    }

    struct MasterKeyFile: Decodable { let master: String? }
    struct ReaderFile: Decodable { let reader: String? }
    struct DoorsFile: Decodable { let doors: [JSONValue]? }
    struct TokenFile: Decodable { let token: String? }

    /// Open the account from PRF bytes or recovery-code bytes. `open` builds a reader for a key
    /// (the app passes one with its server, cache and log).
    public static func unlock(secret: Data, log: VaultTrafficLog,
                              open: @Sendable (VaultKey) async -> SGitVault) async throws -> Keys {
        let start = ContinuousClock.now
        let doorKey = await Task.detached(priority: .userInitiated) { () -> VaultKey in
            VaultDoor.key(for: VaultDoor.door(fromSecret: secret))
        }.value
        await log.record(VaultTrafficEvent(kind: .keyDerivation, path: "passkey → door",
                                           bytes: 32, durationMs: start.elapsedMs,
                                           detail: "HKDF-SHA256 door seed, then PBKDF2 × 2 (600,000 rounds)",
                                           vaultId: doorKey.vaultId))
        let doorVault = await open(doorKey)
        let masterData: Data
        do {
            masterData = try await doorVault.read(doorMasterKeyFile)
        } catch VaultError.vaultNotFoundOrWrongKey {
            throw VaultError.vaultNotFoundOrWrongKey(vaultId: doorKey.vaultId)      // no account for this passkey yet
        }
        let masterFile = try JSONDecoder().decode(MasterKeyFile.self, from: masterData)
        guard let masterText = masterFile.master else {
            throw VaultError.malformed(path: doorMasterKeyFile, detail: "no master key")
        }
        let master = try await SGitVault.deriveKey(from: masterText, log: log)
        let masterVault = await open(master)
        let listed = try await masterVault.files()
        let files = Set(listed.map(\.path))
        var reader: VaultKey?
        if files.contains(masterReaderFile) {
            let data = try await masterVault.read(masterReaderFile)
            if let text = try JSONDecoder().decode(ReaderFile.self, from: data).reader {
                reader = try await SGitVault.deriveKey(from: text, log: log)
            }
        }
        var doorCount = 0
        if files.contains(masterDoorsFile) {
            let data = try await masterVault.read(masterDoorsFile)
            doorCount = (try? JSONDecoder().decode(DoorsFile.self, from: data))?.doors?.count ?? 0
        }
        var token: String?
        if files.contains(masterTokenFile) {
            let data = try await masterVault.read(masterTokenFile)
            token = (try? JSONDecoder().decode(TokenFile.self, from: data))?.token
        }
        return Keys(door: doorKey, master: master, reader: reader, accessToken: token, doorCount: doorCount)
    }

}
