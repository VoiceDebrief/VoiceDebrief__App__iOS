import CryptoKit
import Foundation

/// A file that has been encrypted to disk and is ready to be uploaded and named in a commit.
///
/// Staging is separate from committing so that a long upload can be interrupted and taken up again:
/// the ciphertext stays on disk under its object id, and an object the server already holds is not
/// sent twice.
public struct VaultStagedFile: Sendable, Hashable {
    /// Where the file goes in the vault, e.g. `photos/2026-11-13/IMG_0001.heic`.
    public let path: String
    /// Plaintext bytes.
    public let size: Int
    public let blobId: String
    public let contentHash: String
    public let contentType: String
    /// Over 4 MB encrypted: uploaded in parts, and flagged `large` in the tree, as sgit does.
    public let large: Bool
    public let ciphertextBytes: Int
    /// The encrypted object on disk: iv + ciphertext + tag, exactly what the server will hold.
    public let ciphertext: URL

    public init(path: String, size: Int, blobId: String, contentHash: String, contentType: String, large: Bool,
                ciphertextBytes: Int, ciphertext: URL) {
        self.path = path
        self.size = size
        self.blobId = blobId
        self.contentHash = contentHash
        self.contentType = contentType
        self.large = large
        self.ciphertextBytes = ciphertextBytes
        self.ciphertext = ciphertext
    }
}

/// Encrypts files for one vault, in constant memory.
public struct VaultBlobStager: Sendable {
    public let readKey: SymmetricKey
    /// 12 or 32: the width of object ids in this vault.
    public let idWidth: Int

    public init(readKey: SymmetricKey, idWidth: Int = 12) {
        self.readKey = readKey
        self.idWidth = idWidth
    }

    /// Types sgit (Python's `mimetypes`) records for media, which `VaultCommitBuilder.contentType` lacks.
    static let mediaTypes: [String: String] = [
        "mp4": "video/mp4", "mov": "video/quicktime", "m4v": "video/x-m4v", "avi": "video/x-msvideo",
        "webm": "video/webm", "heic": "image/heic", "heif": "image/heif", "tiff": "image/tiff", "tif": "image/tiff",
        "bmp": "image/bmp", "mp3": "audio/mpeg", "wav": "audio/x-wav", "m4a": "audio/mp4a-latm", "aac": "audio/aac",
    ]

    public static func contentType(for path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let ext = name.split(separator: ".", omittingEmptySubsequences: false).dropFirst().last.map { $0.lowercased() } ?? ""
        return mediaTypes[ext] ?? VaultCommitBuilder.contentType(for: path)
    }

    /// Encrypts `file` into `folder` and names the result by its object id.
    ///
    /// A large file is never deflated, even on a `blob-deflate` vault: the format allows a plain blob
    /// there, photographs and video do not shrink, and deflating would need the file in memory.
    /// - Parameter progress: called with the plaintext bytes encrypted so far.
    public func stage(file: URL, as path: String, in folder: URL,
                      progress: (@Sendable (Int) -> Void)? = nil) async throws -> VaultStagedFile {
        try VaultCommitBuilder.checkPath(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let working = folder.appending(path: "sealing-\(UUID().uuidString)")
        let sealed = try VaultFileCipher.seal(file: file, to: working, key: readKey, progress: progress)
        let blobId = VaultCrypto.objectPrefix + String(sealed.ciphertextSHA256.prefix(idWidth))
        let target = folder.appending(path: blobId)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: working, to: target)
        return VaultStagedFile(path: path, size: sealed.plaintextBytes, blobId: blobId, contentHash: sealed.contentHash,
                               contentType: Self.contentType(for: path),
                               large: sealed.ciphertextBytes > VaultCommitBuilder.largeBlobBytes,
                               ciphertextBytes: sealed.ciphertextBytes, ciphertext: target)
    }
}

/// How one file differs between two commits.
public struct VaultChange: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case added, modified, removed }
    public var id: String { path }
    public let path: String
    public let kind: Kind
    /// The size after the change (before it, for a removed file).
    public let size: Int

    /// What turned `before` into `after`, by path. Two entries are the same file when their blob ids
    /// match, or when their sizes and content hashes do (the same bytes encrypted twice have two ids).
    public static func between(_ before: [VaultFile], _ after: [VaultFile]) -> [VaultChange] {
        var old: [String: VaultFile] = [:]
        for file in before { old[file.path] = file }
        var out: [VaultChange] = []
        for file in after {
            guard let was = old.removeValue(forKey: file.path) else {
                out.append(VaultChange(path: file.path, kind: .added, size: file.size))
                continue
            }
            let sameBytes = was.blobId == file.blobId
                || (was.size == file.size && was.contentHash != nil && was.contentHash == file.contentHash)
            if !sameBytes { out.append(VaultChange(path: file.path, kind: .modified, size: file.size)) }
        }
        for file in old.values { out.append(VaultChange(path: file.path, kind: .removed, size: file.size)) }
        return out.sorted { $0.path < $1.path }
    }
}

extension SGitVault {
    /// A stager for this vault: its read key and the width of its object ids.
    public func stager() async throws -> VaultBlobStager {
        if head == nil { try await pull() }
        return VaultBlobStager(readKey: readKey, idWidth: format?.objectIdWidth ?? 12)
    }

    /// A fingerprint of the public key a commit was signed with: sha256 of the key (X9.63 form), hex,
    /// first 16. The key id in a commit is only a random name; this is the key itself.
    public func signerFingerprint(keyId: String) async throws -> String {
        let allowed = keyId.utf8.allSatisfy { c in
            (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 45 || c == 95
        }
        guard allowed, !keyId.isEmpty, keyId.count <= 128 else {
            throw VaultError.malformed(path: "bare/keys", detail: "unsafe key id")
        }
        let path = "bare/keys/\(keyId)"
        let data = try await fetch(path, cacheable: true)
        let wire: WirePublicKey = try await decode(data, path: path, what: "public key")
        guard let key = try? P256.Signing.PublicKey(pemRepresentation: wire.pem) else {
            throw VaultError.malformed(path: path, detail: "not a P-256 public key")
        }
        return String(Data(SHA256.hash(data: key.x963Representation)).hexString.prefix(16))
    }

    /// The same fingerprint for a signer held on this device.
    public static func fingerprint(of signer: any VaultCommitSigner) -> String? {
        guard let key = try? P256.Signing.PublicKey(pemRepresentation: signer.publicKeyPEM) else { return nil }
        return String(Data(SHA256.hash(data: key.x963Representation)).hexString.prefix(16))
    }

    /// One file of the head, or nil.
    public func file(at path: String) async throws -> VaultFile? {
        if head == nil { try await pull() }
        return fileMap[path]
    }

    /// Commits files that were staged to disk, and removals, on the named branch `branch`, and pushes.
    ///
    /// - Each staged object the server does not hold is uploaded first: in a batch when small, in parts
    ///   through `transport.uploadLarge` when large. `uploaded` is called as each one lands, so the caller
    ///   can record it; pass those ids back as `alreadyUploaded` when trying again.
    /// - Then the trees and the signed commit, then the ref with compare-and-swap.
    /// - A lost race throws `VaultError.pushConflict` and overwrites nothing. Calling again builds the
    ///   commit on the new head: adding files to a vault somebody else also added to needs no merge.
    /// - The branch must exist.
    public func commit(staged: [VaultStagedFile], removing: [String] = [], message: String, branch: String = "current",
                       signer: any VaultCommitSigner, writeKey: SymmetricKey, accessToken: String?,
                       transport writer: any VaultWriteTransport & VaultLargeTransport,
                       alreadyUploaded: Set<String> = [],
                       uploaded: (@Sendable (_ blobId: String) -> Void)? = nil,
                       progress: (@Sendable (_ blobId: String, _ bytesSent: Int) -> Void)? = nil) async throws -> VaultPushResult {
        let start = ContinuousClock.now
        let writeKeyHex = writeKey.withUnsafeBytes { Data($0).hexString }
        let vaultId = address.vaultId

        // 1. Where the branch stands (raw ref bytes for compare-and-swap).
        let indexId = VaultCrypto.branchIndexFileId(readKey: readKey, vaultId: vaultId)
        let indexPath = "bare/indexes/\(indexId)"
        let indexRaw = try await fetch(indexPath, cacheable: false)
        let index: WireBranchIndex = try await decode(indexRaw, path: indexPath, what: "branch index")
        let features = index.features ?? []
        if features.contains("packs") { throw VaultError.unsupportedFormat("writing to a pack vault") }
        guard let entry = index.branches.first(where: { $0.name == branch && ($0.branch_type ?? "named") == "named" }) else {
            throw VaultError.branchNotFound(branch)
        }
        switchBranch(branch)
        let baseHead = try await pull()
        let baseFiles = try await files()
        let refPath = "bare/refs/\(entry.head_ref_id)"
        let refRaw = try await fetch(refPath, cacheable: false)

        // 2. The new set of files, and the commit over it.
        var merged: [String: VaultFile] = [:]
        for file in baseFiles { merged[file.path] = file }
        for path in removing { merged.removeValue(forKey: path) }
        for file in staged {
            try VaultCommitBuilder.checkPath(file.path)
            merged[file.path] = VaultFile(path: file.path, size: file.size, blobId: file.blobId,
                                          contentHash: file.contentHash, contentType: file.contentType, large: file.large)
        }
        let width = format?.objectIdWidth ?? ((index.format ?? 1) >= 2 ? 32 : 12)
        let builder = VaultCommitBuilder(readKey: readKey, idWidth: width, deflateBlobs: false)
        let output = try builder.build(base: Array(merged.values), changes: [:], parents: [baseHead.commitId],
                                       message: message, branchId: entry.branch_id, signer: signer)

        // 3. The staged objects the server does not hold yet.
        var sent = 0
        var bytes = 0
        // Small objects are gathered into batches; a large one travels on its own, in parts.
        var batches: [[VaultStagedFile]] = []
        var batchBytes = 0
        var seen = alreadyUploaded
        for file in staged where !seen.contains(file.blobId) {
            try Task.checkCancellation()
            seen.insert(file.blobId)
            let fileId = "bare/data/\(file.blobId)"
            if file.large {
                let t = ContinuousClock.now
                let id = file.blobId
                try await writer.uploadLarge(vaultId: vaultId, fileId: fileId, from: file.ciphertext,
                                             writeKey: writeKeyHex, accessToken: accessToken) { done in
                    progress?(id, done)
                }
                await emit(.request, fileId, bytes: file.ciphertextBytes, ms: t.elapsedMs, status: 200,
                           detail: "large object, uploaded in parts (\(file.ciphertextBytes.vaultByteString))")
                uploaded?(file.blobId)
                sent += 1
                bytes += file.ciphertextBytes
            } else if let last = batches.last, last.count < 50, batchBytes + file.ciphertextBytes <= 3_000_000 {
                batches[batches.count - 1].append(file)
                batchBytes += file.ciphertextBytes
            } else {
                batches.append([file])
                batchBytes = file.ciphertextBytes
            }
        }
        for batch in batches {
            try Task.checkCancellation()
            var operations: [VaultBatchOperation] = []
            for file in batch {
                operations.append(VaultBatchOperation(op: .write, fileId: "bare/data/\(file.blobId)",
                                                      data: try Data(contentsOf: file.ciphertext)))
            }
            let size = operations.reduce(0) { $0 + $1.data.count }
            let t = ContinuousClock.now
            let result = try await writer.batch(vaultId: vaultId, writeKey: writeKeyHex,
                                                accessToken: accessToken, operations: operations)
            await emit(.request, "batch: \(operations.count) objects", bytes: size, ms: t.elapsedMs, status: 200,
                       detail: "POST write, staged objects")
            guard result == .ok else { throw VaultError.pushConflict(branch: branch) }
            for file in batch {
                uploaded?(file.blobId)
                progress?(file.blobId, file.ciphertextBytes)
            }
            sent += batch.count
            bytes += size
        }

        // 4. Trees and the commit (trees already walked are on the server), and the signer's public key.
        var operations: [VaultBatchOperation] = []
        for (path, data) in output.objects.sorted(by: { $0.key < $1.key }) {
            let id = String(path.dropFirst("bare/data/".count))
            if treeMemo[id] != nil { continue }
            operations.append(VaultBatchOperation(op: .write, fileId: path, data: data))
        }
        let keyPath = "bare/keys/\(signer.keyId)"
        if (try? await transport.get(vaultId: vaultId, path: keyPath))?.status != 200 {
            operations.append(VaultBatchOperation(op: .write, fileId: keyPath,
                                                  data: try builder.publicKeyFile(pem: signer.publicKeyPEM)))
        }
        for startIndex in stride(from: 0, to: operations.count, by: 50) {
            let part = Array(operations[startIndex..<min(startIndex + 50, operations.count)])
            let t = ContinuousClock.now
            let result = try await writer.batch(vaultId: vaultId, writeKey: writeKeyHex,
                                                accessToken: accessToken, operations: part)
            let size = part.reduce(0) { $0 + $1.data.count }
            await emit(.request, "batch: \(part.count) objects", bytes: size, ms: t.elapsedMs, status: 200,
                       detail: "POST write, trees and commit")
            guard result == .ok else { throw VaultError.pushConflict(branch: branch) }
            sent += part.count
            bytes += size
        }

        // 5. The ref, last: compare-and-swap against what was read at the start.
        let newRef = try builder.refValue(commitId: output.commitId)
        let t = ContinuousClock.now
        let moved = try await writer.batch(vaultId: vaultId, writeKey: writeKeyHex, accessToken: accessToken,
                                           operations: [VaultBatchOperation(op: .writeIfMatch, fileId: refPath,
                                                                            data: newRef, match: refRaw)])
        await emit(.request, refPath, bytes: newRef.count, ms: t.elapsedMs, status: 200,
                   detail: "POST move \(branch) (compare-and-swap)")
        guard moved == .ok else {
            try await fail(refPath, .pushConflict(branch: branch))
        }

        // 6. Read back what was pushed.
        let head = try await pull()
        await emit(.verify, "push", bytes: bytes, ms: start.elapsedMs,
                   detail: "pushed \(String(output.commitId.suffix(12))) to \(branch): \(staged.count) files added, \(removing.count) removed, signature \(head.signature.isVerified ? "verified" : "NOT verified")")
        return VaultPushResult(commit: head, branch: branch, createdBranch: false,
                               objectsUploaded: sent + 1, bytesUploaded: bytes)
    }

    /// The largest deflated blob this reader opens through the large path: a deflated blob has to be
    /// inflated in memory.
    public static let largestDeflatedBlobBytes = 64 * 1024 * 1024

    /// Fetches one file of the head into `destination`, checked against its object id, its tag, its size
    /// and its content hash. A large file goes from the network to disk and is decrypted from disk to
    /// disk; it is never held whole in memory.
    /// - Parameters:
    ///   - scratch: a folder for the ciphertext while it is being fetched. It is removed afterwards.
    ///   - progress: called with the ciphertext bytes received so far.
    @discardableResult
    public func download(_ path: String, to destination: URL, scratch: URL, accessToken: String?,
                         transport large: any VaultLargeTransport,
                         progress: (@Sendable (Int) -> Void)? = nil) async throws -> VaultFile {
        if head == nil { try await pull() }
        guard let file = fileMap[path] else { throw VaultError.fileNotFound(path) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !file.large, file.size <= VaultCommitBuilder.largeBlobBytes {
            let data = try await read(path)
            try data.write(to: destination, options: .atomic)
            progress?(data.count)
            return file
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let fetched = scratch.appending(path: "fetching-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fetched) }
        let objectPath = "bare/data/\(file.blobId)"
        let t = ContinuousClock.now
        do {
            try await large.downloadLarge(vaultId: address.vaultId, fileId: objectPath, to: fetched, expectedBytes: nil,
                                          accessToken: accessToken) { done in progress?(done) }
        } catch {
            await emit(.error, objectPath, ms: t.elapsedMs, detail: "large object: \(error.localizedDescription)")
            throw error
        }
        let received = (try? VaultFileCipher.byteCount(of: fetched)) ?? 0
        await emit(.request, objectPath, bytes: received, ms: t.elapsedMs, status: 200,
                   detail: "large object, fetched to disk in ranges (\(received.vaultByteString))")
        let opening = ContinuousClock.now
        do {
            try await Self.openFetched(fetched, file: file, to: destination, readKey: readKey)
        } catch let error as VaultError {
            try await fail(objectPath, error, bytes: received)
        }
        await emit(.decrypt, objectPath, bytes: file.size, ms: opening.elapsedMs,
                   detail: "blob \(path): id, AES-256-GCM tag, size and content hash all match; decrypted from disk to disk")
        return file
    }

    /// Off the actor: hash the ciphertext, decrypt it to `destination`, check what came out.
    private static func openFetched(_ fetched: URL, file: VaultFile, to destination: URL,
                                                readKey: SymmetricKey) async throws {
        let width = VaultCrypto.objectIdWidth(file.blobId)
        let sha = try VaultFileCipher.sha256(of: fetched)
        guard width > 0, VaultCrypto.objectPrefix + String(sha.prefix(width)) == file.blobId else {
            throw VaultError.integrity(objectId: file.blobId, actual: VaultCrypto.objectPrefix + String(sha.prefix(max(width, 12))))
        }
        let structureKey = VaultCrypto.structureKey(readKey: readKey)
        let magic = VaultCrypto.deflateMagic
        var plainBytes = 0
        var contentHash = ""
        if try VaultFileCipher.prefix(of: fetched, count: magic.count) == magic {
            // A deflated blob (sgit wrote it; this writer never deflates a large file).
            let total = try VaultFileCipher.byteCount(of: fetched)
            guard total <= largestDeflatedBlobBytes else { throw VaultError.tooLarge(path: file.path, bytes: total) }
            let data = try Data(contentsOf: fetched, options: .mappedIfSafe)
            let plain: Data
            do {
                plain = try VaultCrypto.open(data, readKey: readKey, structureKey: structureKey).plaintext
            } catch VaultError.inflateFailed {
                throw VaultError.inflateFailed(path: file.path)
            } catch {
                throw VaultError.decryptFailed(path: file.path)
            }
            try plain.write(to: destination, options: .atomic)
            plainBytes = plain.count
            contentHash = VaultCrypto.contentHash(plain)
        } else {
            var opened: VaultFileCipher.Opened?
            for key in [readKey, structureKey] where opened == nil {
                opened = try? VaultFileCipher.open(file: fetched, to: destination, key: key)
                try Task.checkCancellation()
            }
            guard let opened else { throw VaultError.decryptFailed(path: file.path) }
            plainBytes = opened.plaintextBytes
            contentHash = opened.contentHash
        }
        var problem: String?
        if plainBytes != file.size { problem = "size \(plainBytes), tree says \(file.size)" }
        if let expected = file.contentHash, !expected.isEmpty, expected != contentHash {
            problem = "content hash differs from the tree entry"
        }
        if let problem {
            try? FileManager.default.removeItem(at: destination)
            throw VaultError.contentMismatch(path: file.path, detail: problem)
        }
    }
}

extension VaultSync {
    /// The ids of the blobs flagged `large` under `roots`.
    static func largeBlobs(under roots: [String], in transport: any VaultTransport,
                           key: VaultKey) async throws -> Set<String> {
        var seen: Set<String> = []
        var large: Set<String> = []
        var stack = roots.map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            if seen.contains(id) { continue }
            guard depth <= SGitVault.maxTreeDepth else {
                throw VaultError.malformed(path: "bare/data/\(id)", detail: "folders nested deeper than \(SGitVault.maxTreeDepth)")
            }
            seen.insert(id)
            let raw = try await object(id, in: transport, vaultId: key.vaultId)
            let tree: WireTree = try json(raw, key: key, path: "bare/data/\(id)", what: "tree")
            for entry in tree.entries {
                if let sub = entry.tree_id {
                    stack.append((sub, depth + 1))
                } else if let blob = entry.blob_id, entry.large == true, VaultCrypto.objectIdWidth(blob) > 0 {
                    large.insert(blob)
                }
            }
        }
        return large
    }

    /// `transfer`, for a vault that may hold large objects. Those are moved first, each as a file
    /// (fetched to `scratch`, checked against its id, then uploaded in parts), and never held in memory;
    /// `transfer` then sends everything else and moves the ref. Where the destination is ahead or the two
    /// have diverged nothing is sent, exactly as `transfer` behaves.
    /// - Parameter progress: called with a large object's id and the bytes of it moved so far.
    public static func transferWithLargeFiles(key: VaultKey,
                                              from source: any VaultTransport & VaultLargeTransport,
                                              to destination: any VaultRemoteTransport & VaultLargeTransport,
                                              accessToken: String?, scratch: URL, log: VaultTrafficLog? = nil,
                                              progress: (@Sendable (_ blobId: String, _ bytes: Int) -> Void)? = nil) async throws -> VaultSyncResult {
        let vaultId = key.vaultId
        guard let src = try await place(source, key: key) else {
            throw VaultError.vaultNotFoundOrWrongKey(vaultId: vaultId)
        }
        let dst = try await place(destination, key: key)
        if let dst, dst.head == src.head {
            return try await transfer(key: key, from: source, to: destination, accessToken: accessToken, log: log)
        }
        let (fresh, reached) = try await commits(from: src.head, stopAt: dst?.head, in: source, key: key)
        if dst != nil, !reached {
            return try await transfer(key: key, from: source, to: destination, accessToken: accessToken, log: log)
        }
        var have: Set<String> = []
        if let dst {
            let known = try await commit(dst.head, in: source, key: key)
            have = try await largeBlobs(under: [known.tree_id], in: source, key: key)
        }
        let need = try await largeBlobs(under: fresh.map(\.commit.tree_id), in: source, key: key).subtracting(have)
        let writeKeyHex = key.writeKey.map { $0.withUnsafeBytes { Data($0).hexString } } ?? ""
        var moved = 0
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        for id in need.sorted() {
            try Task.checkCancellation()
            let fileId = "bare/data/\(id)"
            let file = scratch.appending(path: "moving-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: file) }
            let t = ContinuousClock.now
            try await source.downloadLarge(vaultId: vaultId, fileId: fileId, to: file, expectedBytes: nil,
                                           accessToken: nil) { _ in }
            let sha = try VaultFileCipher.sha256(of: file)
            let width = VaultCrypto.objectIdWidth(id)
            guard VaultCrypto.objectPrefix + String(sha.prefix(width)) == id else {
                throw VaultError.integrity(objectId: id, actual: VaultCrypto.objectPrefix + String(sha.prefix(width)))
            }
            let size = try VaultFileCipher.byteCount(of: file)
            try await destination.uploadLarge(vaultId: vaultId, fileId: fileId, from: file, writeKey: writeKeyHex,
                                              accessToken: accessToken) { done in progress?(id, done) }
            moved += size
            await log?.record(VaultTrafficEvent(kind: .request, path: fileId, bytes: size, durationMs: t.elapsedMs, status: 200,
                                                detail: "large object, \(source.label) → \(destination.label), as a file",
                                                vaultId: vaultId))
        }
        let rest = try await transfer(key: key, from: source, to: destination, accessToken: accessToken, log: log,
                                      alreadySent: need)
        return VaultSyncResult(outcome: rest.outcome, head: rest.head, commits: rest.commits,
                               objects: rest.objects + need.count, bytes: rest.bytes + moved)
    }
}
