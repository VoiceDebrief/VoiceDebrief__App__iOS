import Foundation

/// Every way a vault operation can fail.
///
/// - `description`: the detail (paths, object ids), for the vault traffic log and tests.
/// - `errorDescription` (`LocalizedError`): short text for people. No paths, ids or keys.
/// Neither ever contains key material.
public enum VaultError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    /// The pasted text is not a key sgit recognises.
    case invalidKey(String)
    /// Neither the branch index nor the default ref exists under ids derived from this key:
    /// the key is wrong, or the vault id is wrong, or the vault was never pushed.
    case vaultNotFoundOrWrongKey(vaultId: String)
    /// A file the server should hold is missing (HTTP 404, or no file in a local folder).
    case notFound(path: String)
    /// The server answered with an unexpected HTTP status.
    case http(status: Int, path: String)
    /// AES-GCM refused the object with both the read key and the structure key.
    case decryptFailed(path: String)
    /// The ciphertext does not hash to its `obj-cas-imm-` id. The object was changed.
    case integrity(objectId: String, actual: String)
    /// A decrypted blob does not match the size or content hash its tree entry records.
    case contentMismatch(path: String, detail: String)
    /// The vault uses a feature this reader does not implement (for example `packs`).
    case unsupportedFormat(String)
    /// Decrypted JSON did not have the expected shape.
    case malformed(path: String, detail: String)
    /// No named branch with that name in the branch index.
    case branchNotFound(String)
    /// No file at that path in the head tree.
    case fileNotFound(String)
    /// The deflate envelope or the zlib stream inside it is damaged, or inflates past the cap.
    case inflateFailed(path: String)
    /// A commit signature does not verify. Always refused.
    case signatureInvalid(commitId: String)
    /// The head commit is unsigned, legacy or its key is missing, and signatures are required.
    case signatureRequired(commitId: String, status: String)
    /// The head commit is signed by a key this device does not trust.
    case untrustedSigner(commitId: String, keyId: String)
    /// A response or object is larger than the reader accepts.
    case tooLarge(path: String, bytes: Int)
    /// The branch moved on the server while pushing. Nothing was overwritten: pull, then push again.
    case pushConflict(branch: String)

    public var description: String {
        switch self {
        case .invalidKey(let why): "Not a vault key: \(why)"
        case .vaultNotFoundOrWrongKey(let id): "Vault \(id) not found with this key (wrong key, wrong vault id, or never pushed)"
        case .notFound(let path): "Not found: \(path)"
        case .http(let status, let path): "HTTP \(status) for \(path)"
        case .decryptFailed(let path): "Could not decrypt \(path) (wrong key or damaged object)"
        case .integrity(let id, let actual): "Object \(id) failed its hash check (ciphertext hashes to \(actual))"
        case .contentMismatch(let path, let detail): "\(path) does not match its tree entry: \(detail)"
        case .unsupportedFormat(let why): "Unsupported vault format: \(why)"
        case .malformed(let path, let detail): "Malformed \(path): \(detail)"
        case .branchNotFound(let name): "No branch named \(name)"
        case .fileNotFound(let path): "No file \(path) in this commit"
        case .inflateFailed(let path): "Could not inflate \(path)"
        case .signatureInvalid(let id): "Commit \(id) has an invalid signature"
        case .signatureRequired(let id, let status): "Commit \(id) is not signed by a verified key (\(status))"
        case .untrustedSigner(let id, let keyId): "Commit \(id) is signed by \(keyId), which this device does not trust"
        case .tooLarge(let path, let bytes): "\(path) is too large (\(bytes) bytes)"
        case .pushConflict(let branch): "\(branch) moved on the server first; nothing was overwritten. Pull and try again."
        }
    }

    /// Short text for people: what happened and what to do. Detail stays in `description`.
    public var errorDescription: String? {
        switch self {
        case .invalidKey(let why): "That is not a vault key: \(why)."
        case .vaultNotFoundOrWrongKey: "No vault opens with this key. Check the key and try again."
        case .notFound, .branchNotFound: "Part of the vault is missing on the server. Try again later."
        case .http(let status, _): "The vault server answered with an error (\(status)). Try again later."
        case .decryptFailed: "Part of the vault could not be decrypted. It may be damaged, or the key is wrong."
        case .integrity, .contentMismatch: "Part of the vault failed its integrity check, so it was not used."
        case .unsupportedFormat: "This vault uses a format the app cannot read yet."
        case .malformed, .inflateFailed: "Part of the vault is damaged, so it was not used."
        case .fileNotFound: "That file is not in the vault."
        case .signatureInvalid: "The latest change to this vault has a broken signature, so it was not used."
        case .signatureRequired: "The latest change to this vault is not signed, so it was not used."
        case .untrustedSigner: "The latest change to this vault was signed by a key this device does not trust yet."
        case .tooLarge: "Part of the vault is too large to open on this device."
        case .pushConflict: "Someone else saved first. Nothing was overwritten; try saving again."
        }
    }
}
