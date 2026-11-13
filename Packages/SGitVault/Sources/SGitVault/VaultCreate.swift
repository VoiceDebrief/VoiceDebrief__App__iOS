import CryptoKit
import Foundation

/// A vault that was just created: its key, and the first commit.
public struct VaultCreated: Sendable {
    public let key: VaultKey
    /// The vault key as text, `sgit_private_vault_<passphrase>:<vault id>`. Secret: it is the only way back in.
    public let keyText: String
    public let commitId: String
    public let branchId: String
}

/// Creating a vault, as `sgit init` does (read from a vault sgit-ai 0.27 made, 13 November 2026):
/// an empty tree, one signed commit with no parent, the named branch `current` whose ref sits at the
/// address derived from the read key, and the branch index. There is no "create vault" endpoint:
/// the server creates the vault on the first write and remembers the hash of the write key that made it.
///
/// Unlike sgit, no clone branch is written: this writer commits straight to named branches.
public enum VaultCreate {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// `count` characters of [a-z0-9] from the system's random source, by rejection sampling so that
    /// no character is favoured (as sgit's generate_vault_key does).
    public static func randomText(_ count: Int) -> String {
        var out = ""
        var generator = SystemRandomNumberGenerator()
        while out.count < count {
            let byte = UInt8.random(in: 0...255, using: &generator)
            if byte < 252 { out.append(alphabet[Int(byte) % 36]) }
        }
        return out
    }

    /// A new vault key: a 24-character passphrase and an 8-character vault id, as sgit generates them.
    public static func newKeyText() -> String {
        "sgit_private_vault_" + randomText(24) + ":" + randomText(8)
    }

    /// The branch index of a new vault, in sgit's member order.
    static func indexJSON(branchId: String, refId: String, keyId: String, timestampMs: Int64) -> PythonJSON {
        .object([
            ("schema", .string("branch_index_v1")),
            ("format", .null),
            ("min_client", .null),
            ("branches", .array([
                .object([
                    ("branch_id", .string(branchId)),
                    ("name", .string("current")),
                    ("branch_type", .string("named")),
                    ("head_ref_id", .string(refId)),
                    ("public_key_id", .string(keyId)),
                    ("private_key_id", .null),
                    ("created_at", .int(timestampMs)),
                    ("creator_branch", .null),
                    ("display_name", .null),
                ]),
            ])),
            ("features", .array([])),
            ("tags", .array([])),
        ])
    }

    /// Creates the vault through `writer`. Deriving the keys takes about a second (PBKDF2, twice):
    /// call it off the main actor.
    ///
    /// - Parameter keyText: a vault key to create at (a passkey's door has a derived one); nil for a new random key.
    public static func create(keyText: String? = nil, signer: any VaultCommitSigner, accessToken: String?,
                              writer: any VaultWriteTransport, message: String = "Vault created",
                              timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async throws -> VaultCreated {
        let text = keyText ?? newKeyText()
        let key = try VaultKey.parse(text)
        guard key.kind == .vault, let writeKey = key.writeKey else {
            throw VaultError.invalidKey("creating a vault needs a vault key, not a read key")
        }
        let builder = VaultCommitBuilder(readKey: key.readKey)
        let branchId = VaultCommitBuilder.newBranchId()
        let output = try builder.build(base: [], changes: [:], parents: [], message: message,
                                       branchId: branchId, signer: signer, timestampMs: timestampMs)
        let refId = VaultCrypto.refFileId(readKey: key.readKey, vaultId: key.vaultId)
        let indexId = VaultCrypto.branchIndexFileId(readKey: key.readKey, vaultId: key.vaultId)

        var operations: [VaultBatchOperation] = []
        for (path, data) in output.objects.sorted(by: { $0.key < $1.key }) {
            operations.append(VaultBatchOperation(op: .write, fileId: path, data: data))
        }
        operations.append(VaultBatchOperation(op: .write, fileId: "bare/keys/\(signer.keyId)",
                                              data: try builder.publicKeyFile(pem: signer.publicKeyPEM)))
        operations.append(VaultBatchOperation(op: .write, fileId: "bare/refs/\(refId)",
                                              data: try builder.refValue(commitId: output.commitId)))
        let index = indexJSON(branchId: branchId, refId: refId, keyId: signer.keyId, timestampMs: timestampMs)
        operations.append(VaultBatchOperation(op: .write, fileId: "bare/indexes/\(indexId)",
                                              data: try VaultCrypto.seal(index.data, key: key.readKey)))

        let writeKeyHex = writeKey.withUnsafeBytes { Data($0).hexString }
        let result = try await writer.batch(vaultId: key.vaultId, writeKey: writeKeyHex,
                                            accessToken: accessToken, operations: operations)
        guard result == .ok else { throw VaultError.pushConflict(branch: "current") }
        return VaultCreated(key: key, keyText: text, commitId: output.commitId, branchId: branchId)
    }
}
