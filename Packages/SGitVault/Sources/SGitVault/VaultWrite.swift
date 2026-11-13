import CryptoKit
import Foundation

/// One operation of `POST /api/vault/batch/<vault id>`.
public struct VaultBatchOperation: Sendable {
    public enum Op: String, Sendable { case write, writeIfMatch = "write-if-match" }
    public let op: Op
    public let fileId: String
    public let data: Data
    /// For `write-if-match`: the exact bytes the file must hold now.
    public let match: Data?

    public init(op: Op, fileId: String, data: Data, match: Data? = nil) {
        self.op = op
        self.fileId = fileId
        self.data = data
        self.match = match
    }

    var json: [String: String] {
        var out = ["op": op.rawValue, "file_id": fileId, "data": data.base64EncodedString()]
        if let match { out["match"] = match.base64EncodedString() }
        return out
    }
}

public enum VaultBatchResult: Sendable, Equatable {
    case ok
    /// A compare-and-swap missed: someone else moved the branch (or the index) first. Nothing was written.
    case conflict(fileId: String?)
}

/// Writes. The server needs the vault's write key (`x-sgraph-vault-write-key`) and an access token
/// (`x-sgraph-access-token`, also sent as `X-API-Key`, as sgit does).
public protocol VaultWriteTransport: Sendable {
    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult
}

extension HTTPVaultTransport: VaultWriteTransport {
    public func batch(vaultId: String, writeKey: String, accessToken: String?,
                      operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var request = URLRequest(url: URL(string: "\(base)/api/vault/batch/\(Self.encode(vaultId))")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(writeKey, forHTTPHeaderField: "x-sgraph-vault-write-key")
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "x-sgraph-access-token")
            request.setValue(accessToken, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operations": operations.map(\.json)])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409 || status == 412 { return .conflict(fileId: nil) }
        guard (200..<300).contains(status) else { throw VaultError.http(status: status, path: "batch") }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (reply["status"] as? String) == "conflict" { return .conflict(fileId: nil) }
        let results = reply["results"] as? [[String: Any]] ?? []
        if let conflict = results.first(where: { ($0["status"] as? String) == "conflict" }) {
            return .conflict(fileId: conflict["file_id"] as? String)
        }
        // A reply that does not answer every operation is not a write (as sgit checks).
        guard results.count == operations.count,
              results.allSatisfy({ ($0["status"] as? String ?? "ok") == "ok" }) else {
            throw VaultError.malformed(path: "batch", detail: "the server answered \(results.count) of \(operations.count) operations")
        }
        return .ok
    }
}

extension FolderVaultTransport: VaultWriteTransport {
    /// Applies the batch to the folder, all or nothing, with compare-and-swap. For tests and local vaults.
    public func batch(vaultId: String, writeKey: String, accessToken: String?,
                      operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        func url(_ fileId: String) -> URL {
            var base = root
            if let sub = perVaultSubfolder {
                base = root.appending(path: vaultId, directoryHint: .isDirectory)
                if !sub.isEmpty { base = base.appending(path: sub, directoryHint: .isDirectory) }
            }
            return base.appending(path: fileId)
        }
        for op in operations where op.op == .writeIfMatch {
            if (try? Data(contentsOf: url(op.fileId))) != op.match { return .conflict(fileId: op.fileId) }
        }
        for op in operations {
            let target = url(op.fileId)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try op.data.write(to: target, options: .atomic)
        }
        return .ok
    }
}

/// What a push did, for the debug panel and tests.
public struct VaultPushResult: Sendable {
    public let commit: VaultCommit
    public let branch: String
    public let createdBranch: Bool
    public let objectsUploaded: Int
    public let bytesUploaded: Int
}

extension SGitVault {
    /// Commit `changes` (path → new content, nil to delete) on the named branch `branch` and push it.
    ///
    /// - If `branch` exists, the commit's parent is its head and the ref moves with compare-and-swap.
    /// - If not, it is created from the head of `from` (default "current"): a new entry in the branch index
    ///   (compare-and-swap on the index) and a new ref. This is the per-device branch.
    /// - The signer's public key is uploaded to `bare/keys/` when the server does not hold it yet.
    /// - A lost race returns `VaultError.pushConflict`; nothing is overwritten. Pull and try again.
    public func commit(_ changes: [String: Data?], message: String, branch: String, from: String = "current",
                       signer: any VaultCommitSigner, writeKey: SymmetricKey, accessToken: String?,
                       writer: any VaultWriteTransport) async throws -> VaultPushResult {
        let start = ContinuousClock.now
        let writeKeyHex = writeKey.withUnsafeBytes { Data($0).hexString }

        // 1. The index as the server holds it now (raw bytes for compare-and-swap).
        let indexId = VaultCrypto.branchIndexFileId(readKey: readKey, vaultId: address.vaultId)
        let indexPath = "bare/indexes/\(indexId)"
        let indexRaw = try await fetch(indexPath, cacheable: false)
        let indexPlain = try await decrypt(indexRaw, path: indexPath, what: "branch index")
        let indexValue = try JSONDecoder().decode(JSONValue.self, from: indexPlain)
        let index = try JSONDecoder().decode(WireBranchIndex.self, from: indexPlain)
        let fmt = VaultFormat(format: index.format ?? 1, minClient: index.min_client, features: index.features ?? [])
        if fmt.features.contains("packs") { throw VaultError.unsupportedFormat("writing to a pack vault") }

        let existing = index.branches.first { $0.name == branch && ($0.branch_type ?? "named") == "named" }
        let baseBranch = existing ?? index.branches.first { $0.name == from && ($0.branch_type ?? "named") == "named" }
        guard let baseBranch else { throw VaultError.branchNotFound(from) }

        // 2. The base head and its files.
        switchBranch(baseBranch.name)
        let baseHead = try await pull()
        let baseFiles = try await files()
        let refPath = "bare/refs/\(baseBranch.head_ref_id)"
        var refRaw: Data?
        if existing != nil { refRaw = try await fetch(refPath, cacheable: false) }

        // 3. Build the commit.
        let branchId = existing?.branch_id ?? VaultCommitBuilder.newBranchId()
        let builder = VaultCommitBuilder(readKey: readKey, idWidth: fmt.objectIdWidth,
                                         deflateBlobs: fmt.features.contains("blob-deflate"))
        let output = try builder.build(base: baseFiles, changes: changes, parents: [baseHead.commitId],
                                       message: message, branchId: branchId, signer: signer)

        // 4. Objects the server does not hold yet (trees already walked are there).
        var operations: [VaultBatchOperation] = []
        for (path, data) in output.objects.sorted(by: { $0.key < $1.key }) {
            let id = String(path.dropFirst("bare/data/".count))
            if treeMemo[id] != nil { continue }
            operations.append(VaultBatchOperation(op: .write, fileId: path, data: data))
        }
        let keyPath = "bare/keys/\(signer.keyId)"
        if (try? await transport.get(vaultId: address.vaultId, path: keyPath))?.status != 200 {
            operations.append(VaultBatchOperation(op: .write, fileId: keyPath,
                                                  data: try builder.publicKeyFile(pem: signer.publicKeyPEM)))
        }

        // 5. The ref (and, for a new branch, the index), last: compare-and-swap.
        let newRef = try builder.refValue(commitId: output.commitId)
        var tail: [VaultBatchOperation] = []
        if let refRaw {
            tail.append(VaultBatchOperation(op: .writeIfMatch, fileId: refPath, data: newRef, match: refRaw))
        } else {
            let refId = VaultCommitBuilder.newRefId()
            guard case .object(var members) = indexValue, case .array(var list) = members["branches"] ?? .array([]) else {
                throw VaultError.malformed(path: indexPath, detail: "no branches list")
            }
            list.append(.object([
                "branch_id": .string(branchId), "name": .string(branch), "branch_type": .string("named"),
                "head_ref_id": .string(refId), "public_key_id": .string(signer.keyId), "private_key_id": .null,
                "created_at": .int(Int64(Date().timeIntervalSince1970 * 1000)), "creator_branch": .null,
                "display_name": .null,
            ]))
            members["branches"] = .array(list)
            let order = ["schema", "format", "min_client", "branches", "features", "tags",
                         "branch_id", "name", "branch_type", "head_ref_id", "public_key_id", "private_key_id",
                         "created_at", "creator_branch", "display_name"]
            let newIndex = try VaultCrypto.seal(PythonJSON(.object(members), order: order).data, key: readKey)
            tail.append(VaultBatchOperation(op: .write, fileId: "bare/refs/\(refId)", data: newRef))
            tail.append(VaultBatchOperation(op: .writeIfMatch, fileId: indexPath, data: newIndex, match: indexRaw))
        }

        // Objects in chunks first (they are immutable, so a partial upload is harmless), then ref and index together.
        let chunk = 50
        var uploaded = 0
        var bytes = 0
        for startIndex in stride(from: 0, to: operations.count, by: chunk) {
            let part = Array(operations[startIndex..<min(startIndex + chunk, operations.count)])
            let t = ContinuousClock.now
            let result = try await writer.batch(vaultId: address.vaultId, writeKey: writeKeyHex,
                                                accessToken: accessToken, operations: part)
            let size = part.reduce(0) { $0 + $1.data.count }
            await emit(.request, "batch: \(part.count) objects", bytes: size, ms: t.elapsedMs, status: 200,
                       detail: "POST write, objects")
            guard result == .ok else { throw VaultError.pushConflict(branch: branch) }
            uploaded += part.count
            bytes += size
        }
        let t = ContinuousClock.now
        let result = try await writer.batch(vaultId: address.vaultId, writeKey: writeKeyHex,
                                            accessToken: accessToken, operations: tail)
        await emit(.request, refPath, bytes: tail.reduce(0) { $0 + $1.data.count }, ms: t.elapsedMs, status: 200,
                   detail: existing == nil ? "POST new branch \(branch): ref + index (compare-and-swap)"
                                           : "POST move \(branch) (compare-and-swap)")
        guard result == .ok else {
            try await fail(refPath, .pushConflict(branch: branch))
        }

        // 6. Read back what was pushed.
        switchBranch(branch)
        let head = try await pull()
        await emit(.verify, "push", bytes: bytes, ms: start.elapsedMs,
                   detail: "pushed \(String(output.commitId.suffix(12))) to \(branch), signature \(head.signature.isVerified ? "verified" : "NOT verified")")
        return VaultPushResult(commit: head, branch: branch, createdBranch: existing == nil,
                               objectsUploaded: uploaded + tail.count, bytesUploaded: bytes)
    }
}
