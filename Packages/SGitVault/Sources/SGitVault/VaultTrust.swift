import Foundation

/// Which author keys a reader accepts for the head commit.
///
/// - `pinnedKeyIds`: keys trusted on this device (this device's signer, keys the user approved,
///   and, on first use, the keys that signed the vault's history at that moment).
/// - A key is also trusted when it is listed in `.vault/trusted-keys.json`
///   (`{"v":1,"keys":["key-rnd-imm-…"]}`) in the newest earlier commit signed by a pinned key.
///   One level only: a listed key cannot list further keys.
/// - A key is never trusted just because its public half sits in `bare/keys/` of the same vault.
public struct VaultTrust: Sendable, Codable, Equatable {
    public static let trustFile = ".vault/trusted-keys.json"
    /// How far back first use looks for signers.
    public static let firstUseDepth = 200
    /// How far back a listing is searched.
    public static let listingSearchDepth = 200

    public var pinnedKeyIds: Set<String>
    /// With no pins yet, pin the history's signers on the first pull instead of refusing.
    public var trustOnFirstUse: Bool

    public init(pinnedKeyIds: Set<String> = [], trustOnFirstUse: Bool = true) {
        self.pinnedKeyIds = pinnedKeyIds
        self.trustOnFirstUse = trustOnFirstUse
    }

    /// The key ids in a trust file; empty when it is malformed.
    public static func listedKeys(in data: Data) -> Set<String> {
        struct File: Decodable { let keys: [String]? }
        let keys = (try? JSONDecoder().decode(File.self, from: data))?.keys ?? []
        return Set(keys.filter { $0.hasPrefix("key-rnd-imm-") })
    }

    /// A trust file listing `keys`, for a commit.
    public static func document(listing keys: Set<String>) -> Data {
        let list = keys.sorted().map { CanonicalJSON.serialize(.string($0)) }.joined(separator: ",")
        return Data("{\"v\":1,\"keys\":[\(list)]}".utf8)
    }
}

extension VaultSignatureStatus {
    /// A short name, for errors and the debug panel.
    public var label: String {
        switch self {
        case .verified: "verified"
        case .unsigned: "unsigned"
        case .invalid: "invalid"
        case .keyMissing: "signing key missing"
        case .legacy: "legacy signature, not checked"
        }
    }
}
