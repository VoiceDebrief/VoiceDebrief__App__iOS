import CryptoKit
import Foundation

/// A parsed vault credential. Holds key bytes in memory only; its `description`
/// never shows them, so it is safe to print or log.
public struct VaultKey: @unchecked Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable {
        /// `sgit_private_vault_<passphrase>:<vault id>`: read and write.
        case vault
        /// `sgit_private_read_<64 hex>:<vault id>`: read only, keep secret.
        case privateRead
        /// `sgit_public_read_<64 hex>:<vault id>`: read only, deliberately published.
        case publicRead
        /// `<64 hex>:<vault id>` with no prefix: treated as a read key.
        case bareRead
    }

    public let kind: Kind
    public let vaultId: String
    public let readKey: SymmetricKey
    /// Only for `.vault` keys.
    public let writeKey: SymmetricKey?

    public var canWrite: Bool { writeKey != nil }

    public var description: String { "VaultKey(\(kind.rawValue), vault \(vaultId))" }

    public init(kind: Kind, vaultId: String, readKey: SymmetricKey, writeKey: SymmetricKey? = nil) {
        self.kind = kind
        self.vaultId = vaultId
        self.readKey = readKey
        self.writeKey = writeKey
    }

    static let vaultPrefixes = ["sgit_private_vault_", "sgit_vk1_"]
    static let privateReadPrefixes = ["sgit_private_read_", "sgit_rk1_"]
    static let publicReadPrefixes = ["sgit_public_read_"]

    /// sgit's vault id rule: 4–24 lowercase letters and digits.
    public static func isValidVaultId(_ id: String) -> Bool {
        (4...24).contains(id.count) && id.unicodeScalars.allSatisfy { scalar in
            (97...122).contains(scalar.value) || (48...57).contains(scalar.value)
        }
    }

    /// What the pasted text declares itself to be, without deriving anything.
    /// Cheap: no PBKDF2. Use it to decide whether to show a progress indicator.
    public static func classify(_ text: String) -> Kind? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if vaultPrefixes.contains(where: { key.hasPrefix($0) }) { return .vault }
        if privateReadPrefixes.contains(where: { key.hasPrefix($0) }) { return .privateRead }
        if publicReadPrefixes.contains(where: { key.hasPrefix($0) }) { return .publicRead }
        guard let colon = key.lastIndex(of: ":") else { return nil }
        let body = key[..<colon]
        if body.count == 64, body.allSatisfy(\.isHexDigit) { return .bareRead }
        return .vault   // a bare passphrase:vault_id, as sgit's own key files hold
    }

    /// Parse a pasted or scanned key. A vault key runs PBKDF2 twice (600,000 rounds each),
    /// so call it off the main actor. `vaultId` is used when the text has none.
    public static func parse(_ text: String, vaultId fallbackVaultId: String? = nil) throws -> VaultKey {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VaultError.invalidKey("empty") }
        guard let kind = classify(key) else {
            throw VaultError.invalidKey("expected sgit_private_read_<64 hex>:<vault id> or sgit_private_vault_<passphrase>:<vault id>")
        }
        var body = key
        for prefix in vaultPrefixes + privateReadPrefixes + publicReadPrefixes where body.hasPrefix(prefix) {
            body = String(body.dropFirst(prefix.count))
            break
        }
        var secret = body
        var vaultId = fallbackVaultId ?? ""
        if let colon = body.lastIndex(of: ":") {
            secret = String(body[..<colon])
            vaultId = String(body[body.index(after: colon)...])
        }
        guard !secret.isEmpty else { throw VaultError.invalidKey("no key before the vault id") }
        guard isValidVaultId(vaultId) else {
            throw VaultError.invalidKey("the vault id must be 4 to 24 lowercase letters and digits")
        }
        switch kind {
        case .vault:
            return VaultKey(kind: .vault, vaultId: vaultId,
                            readKey: VaultCrypto.deriveReadKey(passphrase: secret, vaultId: vaultId),
                            writeKey: VaultCrypto.deriveWriteKey(passphrase: secret, vaultId: vaultId))
        case .privateRead, .publicRead, .bareRead:
            guard secret.count == 64, let bytes = Data(hexString: secret) else {
                throw VaultError.invalidKey("a read key is 64 hex characters")
            }
            return VaultKey(kind: kind, vaultId: vaultId, readKey: SymmetricKey(data: bytes))
        }
    }

    /// The read key in sgit's display form, for export (a QR code, the clipboard). Handle with care.
    public func exportReadKey(public isPublic: Bool = false) -> String {
        let hex = readKey.withUnsafeBytes { Data($0).hexString }
        return (isPublic ? "sgit_public_read_" : "sgit_private_read_") + hex + ":" + vaultId
    }
}
