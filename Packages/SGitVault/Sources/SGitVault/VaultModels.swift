import Foundation

/// Where a vault lives. Reads are `GET <server>/api/vault/read/<vaultId>/<url-encoded path>`.
public struct VaultAddress: Sendable, Hashable, Codable {
    public let vaultId: String
    public let server: URL

    public static let defaultServer = URL(string: "https://dev.send.sgraph.ai")!

    public init(vaultId: String, server: URL = VaultAddress.defaultServer) {
        self.vaultId = vaultId
        self.server = server
    }
}

/// A branch from the branch index.
public struct VaultBranch: Sendable, Hashable, Identifiable, Codable {
    public enum BranchType: String, Sendable, Codable { case named, clone, other }
    public var id: String { branchId }
    public let branchId: String
    public let name: String
    public let type: BranchType
    public let headRefId: String
    public let publicKeyId: String?
    public let createdAt: Date?
    public let creatorBranch: String?
}

/// The format gate from the branch index.
public struct VaultFormat: Sendable, Hashable, Codable {
    public let format: Int
    public let minClient: String?
    public let features: [String]
    public var objectIdWidth: Int { format >= 2 ? 32 : 12 }
}

/// What a commit signature check found.
public enum VaultSignatureStatus: Sendable, Hashable, Codable {
    /// ECDSA P-256 over sgit's canonical bytes, with the author key from `bare/keys/`.
    case verified(keyId: String)
    case unsigned
    /// The signature does not verify with the named key.
    case invalid(keyId: String)
    /// The commit names a key the server does not hold.
    case keyMissing(keyId: String)
    /// Signed before sgit had `author_key_id`: not checked by this reader.
    case legacy

    public var isVerified: Bool { if case .verified = self { true } else { false } }
}

public struct VaultCommit: Sendable, Hashable, Identifiable {
    public var id: String { commitId }
    public let commitId: String
    public let treeId: String
    public let parents: [String]
    public let message: String
    public let timestamp: Date
    public let branchId: String?
    public let authorKeyId: String?
    public let signature: VaultSignatureStatus
}

public struct VaultFile: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let size: Int
    public let blobId: String
    public let contentHash: String?
    public let contentType: String?
    public let large: Bool
}

/// A node of the decrypted tree, for the inspector.
public struct VaultTreeNode: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let objectId: String
    public let isFolder: Bool
    /// File size, or the sum of the sizes below a folder.
    public let size: Int
    public let children: [VaultTreeNode]
}

// MARK: Wire shapes (decrypted JSON)

struct WireBranchIndex: Decodable {
    let schema: String?
    let format: Int?
    let min_client: String?
    let branches: [WireBranch]
    let features: [String]?
}

struct WireBranch: Decodable {
    let branch_id: String
    let name: String
    let branch_type: String?
    let head_ref_id: String
    let public_key_id: String?
    let created_at: Double?
    let creator_branch: String?
}

struct WireRef: Decodable {
    let commit_id: String?
}

struct WireCommit: Decodable {
    let schema: String?
    let tree_id: String
    let message_enc: String?
    let branch_id: String?
    let signature: String?
    let author_key_id: String?
    let parents: [String]?
    let timestamp_ms: Double?
}

struct WireTree: Decodable {
    let schema: String?
    let entries: [WireTreeEntry]
}

struct WireTreeEntry: Decodable {
    let blob_id: String?
    let tree_id: String?
    let name_enc: String
    let size_enc: String?
    let content_hash_enc: String?
    let content_type_enc: String?
    let large: Bool?
}

struct WirePublicKey: Decodable {
    let type: String?
    let pem: String
}
