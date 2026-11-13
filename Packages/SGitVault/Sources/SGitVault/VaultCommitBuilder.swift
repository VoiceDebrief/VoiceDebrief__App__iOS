import CryptoKit
import Foundation

/// Signs commits. sgit signs with ECDSA P-256 over SHA-256 and stores the raw r‖s (64 bytes), base64.
public protocol VaultCommitSigner: Sendable {
    /// `key-rnd-imm-<16 hex>`: where the public key is stored, `bare/keys/<keyId>`.
    var keyId: String { get }
    /// The public key, PEM (SubjectPublicKeyInfo).
    var publicKeyPEM: String { get }
    /// Raw r‖s signature (64 bytes) over `data`, hashed with SHA-256.
    func sign(_ data: Data) throws -> Data
}

/// A software P-256 key (tests, and devices without a Secure Enclave).
public struct SoftwareCommitSigner: VaultCommitSigner {
    public let keyId: String
    let privateKey: P256.Signing.PrivateKey

    public init(privateKey: P256.Signing.PrivateKey = .init(), keyId: String? = nil) {
        self.privateKey = privateKey
        self.keyId = keyId ?? VaultCommitBuilder.newKeyId()
    }

    public var publicKeyPEM: String { privateKey.publicKey.pemRepresentation }
    public func sign(_ data: Data) throws -> Data { try privateKey.signature(for: data).rawRepresentation }
}

/// Builds sgit objects: blobs, trees, a signed commit and the ref value, byte-compatible with sgit-ai 0.27.
///
/// - blobs: iv + AES-GCM(content), random iv; deflated (`\0sgz1`) on a `blob-deflate` vault when smaller
/// - trees: `json.dumps({"schema": "tree_v1", "entries": [...]})`, files by name then folders by name,
///   every name/size/hash/type field and the tree itself encrypted deterministically (iv = HMAC(key, plaintext)[:12])
/// - commit: `commit_v1`, message encrypted with a random iv, signed over the canonical bytes (RFC 8785)
/// - ids: `obj-cas-imm-` + sha256(ciphertext), 12 hex (format 1) or 32 hex (format 2)
public struct VaultCommitBuilder: Sendable {
    public let readKey: SymmetricKey
    public let idWidth: Int
    public let deflateBlobs: Bool
    /// sgit refuses commit messages over 740 bytes on vaults without `long-messages`.
    public static let shortMessageBytes = 740
    /// sgit uploads larger blobs through presigned multipart URLs; not implemented here.
    public static let largeBlobBytes = 4 * 1024 * 1024

    public init(readKey: SymmetricKey, idWidth: Int = 12, deflateBlobs: Bool = false) {
        self.readKey = readKey
        self.idWidth = idWidth
        self.deflateBlobs = deflateBlobs
    }

    public struct Output: Sendable {
        public let commitId: String
        public let treeId: String
        /// Every object this commit needs, by server path (`bare/data/<id>`). Includes unchanged trees,
        /// which the pusher can skip when the server already holds them.
        public let objects: [String: Data]
        /// The new blobs only (changed files).
        public let newBlobIds: Set<String>
        public let files: [VaultFile]
    }

    public enum BuildError: Error, Equatable, CustomStringConvertible {
        case messageTooLong(Int)
        case blobTooLarge(String)
        case badPath(String)
        public var description: String {
            switch self {
            case .messageTooLong(let n): "Commit message is \(n) bytes; sgit allows 740"
            case .blobTooLarge(let p): "\(p) is over 4 MB encrypted; large uploads are not implemented"
            case .badPath(let p): "Not a valid vault path: \(p)"
            }
        }
    }

    public static func newKeyId() -> String { "key-rnd-imm-" + randomHex(8) }
    public static func newBranchId() -> String { "branch-named-" + randomHex(8) }
    public static func newRefId() -> String { "ref-pid-muw-" + randomHex(6) }

    static func randomHex(_ bytes: Int) -> String {
        Data(SymmetricKey(size: SymmetricKeySize(bitCount: bytes * 8)).withUnsafeBytes { Data($0) }).hexString
    }

    // MARK: Objects

    func objectId(_ ciphertext: Data) -> String { VaultCrypto.objectId(of: ciphertext, width: idWidth) }

    func detMeta(_ text: String) throws -> String {
        try VaultCrypto.sealDeterministic(Data(text.utf8), key: readKey).base64EncodedString()
    }

    public func encryptBlob(_ content: Data) throws -> Data {
        if deflateBlobs, let packed = Zlib.compress(content), packed.count + VaultCrypto.deflateMagic.count < content.count {
            return VaultCrypto.deflateMagic + (try VaultCrypto.seal(packed, key: readKey))
        }
        return try VaultCrypto.seal(content, key: readKey)
    }

    /// The ref value: `{"commit_id": "<id>"}`, random iv.
    public func refValue(commitId: String) throws -> Data {
        try VaultCrypto.seal(PythonJSON.object([("commit_id", .string(commitId))]).data, key: readKey)
    }

    /// The public key file `bare/keys/<id>`: `{"type": "public", "pem": "…"}`, random iv.
    public func publicKeyFile(pem: String) throws -> Data {
        let text = pem.hasSuffix("\n") ? pem : pem + "\n"
        return try VaultCrypto.seal(PythonJSON.object([("type", .string("public")), ("pem", .string(text))]).data, key: readKey)
    }

    // MARK: Build

    /// `base`: the files of the parent commit (as `SGitVault.files()` returns them).
    /// `changes`: path → new content, or nil to delete.
    public func build(base: [VaultFile], changes: [String: Data?], parents: [String], message: String,
                      branchId: String, signer: any VaultCommitSigner,
                      timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> Output {
        guard message.utf8.count <= Self.shortMessageBytes else { throw BuildError.messageTooLong(message.utf8.count) }
        var objects: [String: Data] = [:]
        var newBlobs: Set<String> = []
        var files: [String: VaultFile] = [:]
        for file in base { files[file.path] = file }
        for (path, content) in changes {
            try Self.checkPath(path)
            guard let content else { files.removeValue(forKey: path); continue }
            let ciphertext = try encryptBlob(content)
            guard ciphertext.count <= Self.largeBlobBytes else { throw BuildError.blobTooLarge(path) }
            let id = objectId(ciphertext)
            objects["bare/data/\(id)"] = ciphertext
            newBlobs.insert(id)
            files[path] = VaultFile(path: path, size: content.count, blobId: id,
                                    contentHash: VaultCrypto.contentHash(content),
                                    contentType: Self.contentType(for: path), large: false)
        }
        let treeId = try buildTrees(files: Array(files.values), objects: &objects)

        // The commit, in sgit's member order, then signed over its canonical form.
        let messageEnc = try VaultCrypto.seal(Data(message.utf8), key: readKey).base64EncodedString()
        func commitJSON(signature: String?) -> PythonJSON {
            .object([
                ("schema", .string("commit_v1")),
                ("tree_id", .string(treeId)),
                ("message_enc", .string(messageEnc)),
                ("branch_id", .string(branchId)),
                ("signature", .str(signature)),
                ("author_key_id", .string(signer.keyId)),
                ("author_signature", .null),
                ("parents", .array(parents.map { .string($0) })),
                ("timestamp_ms", .int(timestampMs)),
                ("attestations", .array([])),
            ])
        }
        let signingBytes = try CanonicalJSON.signingBytes(commitJSON: commitJSON(signature: nil).data)
        let signature = try signer.sign(signingBytes).base64EncodedString()
        let commit = try VaultCrypto.seal(commitJSON(signature: signature).data, key: readKey)
        let commitId = objectId(commit)
        objects["bare/data/\(commitId)"] = commit
        return Output(commitId: commitId, treeId: treeId, objects: objects, newBlobIds: newBlobs,
                      files: files.values.sorted { $0.path < $1.path })
    }

    static func checkPath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BuildError.badPath(path)
        }
    }

    /// Python sorts strings by code point.
    static func pyLess(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.map(\.value).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
    }

    private func buildTrees(files: [VaultFile], objects: inout [String: Data]) throws -> String {
        // folder path ("" = root) → files directly in it, and child folder names
        var direct: [String: [(String, VaultFile)]] = ["": []]
        var children: [String: Set<String>] = [:]
        for file in files {
            let parts = file.path.split(separator: "/").map(String.init)
            var folder = ""
            for part in parts.dropLast() {
                let child = folder.isEmpty ? part : folder + "/" + part
                children[folder, default: []].insert(part)
                direct[child, default: []] += []
                folder = child
            }
            guard let name = parts.last else { continue }      // an empty path never reaches here (checkPath)
            direct[folder, default: []].append((name, file))
        }
        // Deepest folders first.
        let folders = direct.keys.sorted { a, b in
            let da = a.isEmpty ? 0 : a.split(separator: "/").count
            let db = b.isEmpty ? 0 : b.split(separator: "/").count
            return da != db ? da > db : Self.pyLess(a, b)
        }
        var treeIds: [String: String] = [:]
        for folder in folders {
            var entries: [PythonJSON] = []
            for (name, file) in (direct[folder] ?? []).sorted(by: { Self.pyLess($0.0, $1.0) }) {
                entries.append(.object([
                    ("blob_id", .string(file.blobId)),
                    ("tree_id", .null),
                    ("name_enc", .string(try detMeta(name))),
                    ("size_enc", .string(try detMeta(String(file.size)))),
                    ("content_hash_enc", .string(try detMeta(file.contentHash ?? ""))),
                    ("content_type_enc", .string(try detMeta(file.contentType ?? Self.contentType(for: name)))),
                    ("large", .bool(file.large)),
                ]))
            }
            for name in (children[folder] ?? []).sorted(by: Self.pyLess) {
                let child = folder.isEmpty ? name : folder + "/" + name
                guard let childId = treeIds[child] else { continue }
                entries.append(.object([
                    ("blob_id", .null),
                    ("tree_id", .string(childId)),
                    ("name_enc", .string(try detMeta(name))),
                    ("size_enc", .null),
                    ("content_hash_enc", .null),
                    ("content_type_enc", .null),
                    ("large", .bool(false)),
                ]))
            }
            let tree = PythonJSON.object([("schema", .string("tree_v1")), ("entries", .array(entries))])
            let ciphertext = try VaultCrypto.sealDeterministic(tree.data, key: readKey)
            let id = objectId(ciphertext)
            objects["bare/data/\(id)"] = ciphertext
            treeIds[folder] = id
        }
        return treeIds[""]!
    }

    /// The MIME type sgit records (Python's `mimetypes.guess_type`, for common extensions).
    public static func contentType(for path: String) -> String {
        let ext = (path.split(separator: "/").last.map(String.init) ?? path)
            .split(separator: ".", omittingEmptySubsequences: false).dropFirst().last.map { $0.lowercased() } ?? ""
        let table: [String: String] = [
            "md": "text/markdown", "markdown": "text/markdown", "txt": "text/plain", "json": "application/json",
            "html": "text/html", "htm": "text/html", "css": "text/css", "js": "text/javascript",
            "mjs": "text/javascript", "csv": "text/csv", "xml": "text/xml", "svg": "image/svg+xml",
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "pdf": "application/pdf", "zip": "application/zip", "py": "text/x-python",
            "yaml": "application/yaml", "yml": "application/yaml",
        ]
        return table[ext] ?? "application/octet-stream"
    }
}
