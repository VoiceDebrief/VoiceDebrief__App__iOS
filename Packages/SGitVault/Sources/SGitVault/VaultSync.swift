import CryptoKit
import Foundation

/// A place a vault can be pushed to: it answers reads and takes batches. The server and a folder both do.
public typealias VaultRemoteTransport = VaultTransport & VaultWriteTransport

/// What a transfer did.
public struct VaultSyncResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Both places already held the same head. Nothing was sent.
        case upToDate
        /// The destination did not hold the vault: everything was sent, then the ref and the branch index.
        case created
        /// The destination's head was an ancestor of the source's: the missing objects were sent and the
        /// ref moved with compare-and-swap.
        case fastForwarded
        /// The source's head is an ancestor of the destination's: the destination is ahead. Nothing was sent.
        case sourceBehind
        /// Each place has commits the other lacks. That needs a merge, which is not built. Nothing was sent
        /// and no ref moved.
        case diverged
    }

    public let outcome: Outcome
    /// The destination's head after the transfer (unchanged for `sourceBehind` and `diverged`).
    public let head: String
    public let commits: Int
    public let objects: Int
    public let bytes: Int

    public var moved: Bool { outcome == .created || outcome == .fastForwarded }
}

/// Moving the named branch `current` of one vault between two places that hold it in the server's
/// layout (`bare/…`): a folder on the device and a server, in either direction. A push is a transfer
/// from the folder to the server; a pull is the same transfer the other way.
///
/// - Objects are content-addressed and immutable, so sending one twice is harmless. Each is checked
///   against its id before it is written anywhere.
/// - Only what the destination's head cannot already reach is sent.
/// - The ref moves last, and only forward: with compare-and-swap against the bytes the destination held
///   when the transfer began. A ref is never moved unconditionally. Where the two places have diverged
///   nothing is written at all.
/// - Only `current` moves. Other branches named in the index are left as they are.
/// - A vault without a branch index (older sgit) or with packs is refused.
public enum VaultSync {
    public static let branch = "current"
    /// The most commits a transfer walks before giving up.
    public static let maxCommits = 20_000

    /// Where `current` stands in one place.
    struct Place {
        let indexRaw: Data
        let refPath: String
        let refRaw: Data
        let head: String
    }

    struct Walked {
        let id: String
        let commit: WireCommit
    }

    // MARK: Reading

    /// Names that become part of a path must be plain: a hostile index or commit cannot name `../x`.
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 128 && name.utf8.allSatisfy { c in
            (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 45 || c == 95
        }
    }

    static func plain(_ raw: Data, key: VaultKey, path: String) throws -> Data {
        do {
            return try VaultCrypto.open(raw, readKey: key.readKey,
                                        structureKey: VaultCrypto.structureKey(readKey: key.readKey)).plaintext
        } catch {
            throw VaultError.decryptFailed(path: path)
        }
    }

    static func json<T: Decodable>(_ raw: Data, key: VaultKey, path: String, what: String) throws -> T {
        let data = try plain(raw, key: key, path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw VaultError.malformed(path: path, detail: "\(what) JSON has an unexpected shape")
        }
    }

    /// One object's ciphertext, checked against its id.
    static func object(_ id: String, in transport: any VaultTransport, vaultId: String) async throws -> Data {
        guard VaultCrypto.objectIdWidth(id) > 0 else {
            throw VaultError.malformed(path: id, detail: "not an obj-cas-imm id")
        }
        let path = "bare/data/\(id)"
        let response = try await transport.get(vaultId: vaultId, path: path)
        if response.status == 404 { throw VaultError.notFound(path: path) }
        guard response.status == 200 else { throw VaultError.http(status: response.status, path: path) }
        guard VaultCrypto.objectIdMatches(id, ciphertext: response.data) else {
            throw VaultError.integrity(objectId: id, actual: VaultCrypto.objectId(of: response.data,
                                                                                   width: VaultCrypto.objectIdWidth(id)))
        }
        return response.data
    }

    /// Where `current` stands in `transport`, or nil when the vault is not there at all.
    static func place(_ transport: any VaultTransport, key: VaultKey) async throws -> Place? {
        let indexPath = "bare/indexes/\(VaultCrypto.branchIndexFileId(readKey: key.readKey, vaultId: key.vaultId))"
        let indexResponse = try await transport.get(vaultId: key.vaultId, path: indexPath)
        if indexResponse.status == 404 { return nil }
        guard indexResponse.status == 200 else { throw VaultError.http(status: indexResponse.status, path: indexPath) }
        let index: WireBranchIndex = try json(indexResponse.data, key: key, path: indexPath, what: "branch index")
        if (index.features ?? []).contains("packs") { throw VaultError.unsupportedFormat("moving a pack vault") }
        guard let entry = index.branches.first(where: { $0.name == branch && ($0.branch_type ?? "named") == "named" }) else {
            throw VaultError.branchNotFound(branch)
        }
        guard isSafeName(entry.head_ref_id) else {
            throw VaultError.malformed(path: indexPath, detail: "unsafe ref id")
        }
        let refPath = "bare/refs/\(entry.head_ref_id)"
        let refResponse = try await transport.get(vaultId: key.vaultId, path: refPath)
        if refResponse.status == 404 { throw VaultError.notFound(path: refPath) }
        guard refResponse.status == 200 else { throw VaultError.http(status: refResponse.status, path: refPath) }
        let ref: WireRef = try json(refResponse.data, key: key, path: refPath, what: "ref")
        guard let head = ref.commit_id, VaultCrypto.objectIdWidth(head) > 0 else {
            throw VaultError.malformed(path: refPath, detail: "no commit id")
        }
        return Place(indexRaw: indexResponse.data, refPath: refPath, refRaw: refResponse.data, head: head)
    }

    static func commit(_ id: String, in transport: any VaultTransport, key: VaultKey) async throws -> WireCommit {
        let raw = try await object(id, in: transport, vaultId: key.vaultId)
        return try json(raw, key: key, path: "bare/data/\(id)", what: "commit")
    }

    /// The commits reachable from `start`, newest first, not going past `stop`; and whether `stop` was met
    /// (that is, whether `stop` is an ancestor of `start`).
    static func commits(from start: String, stopAt stop: String?, in transport: any VaultTransport,
                        key: VaultKey) async throws -> (walked: [Walked], reachedStop: Bool) {
        var walked: [Walked] = []
        var reached = false
        var seen: Set<String> = [start]
        var queue = [start]
        var next = 0
        while next < queue.count {
            let id = queue[next]
            next += 1
            if id == stop {
                reached = true
                continue
            }
            guard walked.count < maxCommits else {
                throw VaultError.tooLarge(path: "history", bytes: walked.count)
            }
            let wire = try await commit(id, in: transport, key: key)
            walked.append(Walked(id: id, commit: wire))
            for parent in wire.parents ?? [] where !seen.contains(parent) {
                seen.insert(parent)
                queue.append(parent)
            }
        }
        return (walked, reached)
    }

    /// Every tree and blob id below `roots`, not descending into `skipping` (trees the other side holds whole).
    static func closure(of roots: [String], skipping: Set<String> = [], in transport: any VaultTransport,
                        key: VaultKey) async throws -> (trees: Set<String>, blobs: Set<String>) {
        var trees: Set<String> = []
        var blobs: Set<String> = []
        var stack = roots.map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            if trees.contains(id) || skipping.contains(id) { continue }
            guard depth <= SGitVault.maxTreeDepth else {
                throw VaultError.malformed(path: "bare/data/\(id)", detail: "folders nested deeper than \(SGitVault.maxTreeDepth)")
            }
            trees.insert(id)
            let raw = try await object(id, in: transport, vaultId: key.vaultId)
            let tree: WireTree = try json(raw, key: key, path: "bare/data/\(id)", what: "tree")
            for entry in tree.entries {
                if let sub = entry.tree_id {
                    stack.append((sub, depth + 1))
                } else if let blob = entry.blob_id {
                    blobs.insert(blob)
                }
            }
        }
        return (trees, blobs)
    }

    // MARK: Transfer

    /// Brings `destination` up to `source` on the branch `current`, if that is a creation or a fast-forward.
    /// Otherwise it reports where the two stand and writes nothing.
    ///
    /// - Parameter accessToken: what the destination needs for writes (a server's token; nil for a folder).
    /// - Throws: `VaultError.vaultNotFoundOrWrongKey` when the source does not hold the vault;
    ///   `VaultError.pushConflict` when the destination's ref moved during the transfer (nothing is overwritten).
    public static func transfer(key: VaultKey, from source: any VaultTransport,
                                to destination: any VaultRemoteTransport, accessToken: String?,
                                log: VaultTrafficLog? = nil,
                                alreadySent: Set<String> = []) async throws -> VaultSyncResult {
        let start = ContinuousClock.now
        let vaultId = key.vaultId
        guard let src = try await place(source, key: key) else {
            throw VaultError.vaultNotFoundOrWrongKey(vaultId: vaultId)
        }
        let dst = try await place(destination, key: key)
        if let dst, dst.head == src.head {
            return VaultSyncResult(outcome: .upToDate, head: src.head, commits: 0, objects: 0, bytes: 0)
        }

        // What the source has that the destination's head does not reach.
        let (fresh, reached) = try await commits(from: src.head, stopAt: dst?.head, in: source, key: key)
        if let dst, !reached {
            let (_, behind) = try await commits(from: dst.head, stopAt: src.head, in: destination, key: key)
            await log?.record(VaultTrafficEvent(kind: .verify, path: "sync", durationMs: start.elapsedMs,
                detail: behind ? "\(source.label) is behind \(destination.label): nothing sent"
                               : "\(source.label) and \(destination.label) have diverged: nothing sent, no ref moved",
                vaultId: vaultId))
            return VaultSyncResult(outcome: behind ? .sourceBehind : .diverged, head: dst.head,
                                   commits: 0, objects: 0, bytes: 0)
        }

        var haveTrees: Set<String> = []
        var haveBlobs: Set<String> = []
        if let dst {
            let known = try await commit(dst.head, in: source, key: key)
            (haveTrees, haveBlobs) = try await closure(of: [known.tree_id], in: source, key: key)
        }
        let need = try await closure(of: fresh.map(\.commit.tree_id), skipping: haveTrees, in: source, key: key)
        // `alreadySent`: blobs the caller has delivered by another route (large objects, sent as files).
        let ids = need.blobs.subtracting(haveBlobs).subtracting(alreadySent).sorted() + need.trees.sorted() + fresh.map(\.id)

        let writeKeyHex = key.writeKey.map { $0.withUnsafeBytes { Data($0).hexString } } ?? ""
        var sent = 0
        var bytes = 0
        var pending: [VaultBatchOperation] = []
        var pendingBytes = 0

        func flush() async throws {
            guard !pending.isEmpty else { return }
            let t = ContinuousClock.now
            let result = try await destination.batch(vaultId: vaultId, writeKey: writeKeyHex,
                                                     accessToken: accessToken, operations: pending)
            await log?.record(VaultTrafficEvent(kind: .request, path: "batch: \(pending.count) objects", bytes: pendingBytes,
                                                durationMs: t.elapsedMs, status: 200,
                                                detail: "write to \(destination.label), objects", vaultId: vaultId))
            guard result == .ok else { throw VaultError.pushConflict(branch: branch) }
            sent += pending.count
            bytes += pendingBytes
            pending = []
            pendingBytes = 0
        }

        for id in ids {
            let data = try await object(id, in: source, vaultId: vaultId)
            if !pending.isEmpty, pending.count >= VaultBatchOperation.batchCount
                || pendingBytes + data.count > VaultBatchOperation.batchBytes {
                try await flush()
            }
            pending.append(VaultBatchOperation(op: .write, fileId: "bare/data/\(id)", data: data))
            pendingBytes += data.count
        }

        // The public keys the new commits were signed with, where the destination lacks them.
        for keyId in Set(fresh.compactMap(\.commit.author_key_id)).sorted() where isSafeName(keyId) {
            let path = "bare/keys/\(keyId)"
            if (try? await destination.get(vaultId: vaultId, path: path))?.status == 200 { continue }
            let held = try await source.get(vaultId: vaultId, path: path)
            guard held.status == 200 else { continue }
            pending.append(VaultBatchOperation(op: .write, fileId: path, data: held.data))
            pendingBytes += held.data.count
        }
        try await flush()

        // The ref last. Onto an existing vault: compare-and-swap against what was read at the start.
        let tail: [VaultBatchOperation]
        if let dst {
            tail = [VaultBatchOperation(op: .writeIfMatch, fileId: dst.refPath, data: src.refRaw, match: dst.refRaw)]
        } else {
            let indexPath = "bare/indexes/\(VaultCrypto.branchIndexFileId(readKey: key.readKey, vaultId: vaultId))"
            tail = [VaultBatchOperation(op: .write, fileId: src.refPath, data: src.refRaw),
                    VaultBatchOperation(op: .write, fileId: indexPath, data: src.indexRaw)]
        }
        let t = ContinuousClock.now
        let result = try await destination.batch(vaultId: vaultId, writeKey: writeKeyHex,
                                                 accessToken: accessToken, operations: tail)
        await log?.record(VaultTrafficEvent(kind: .request, path: dst?.refPath ?? src.refPath,
                                            bytes: tail.reduce(0) { $0 + $1.data.count }, durationMs: t.elapsedMs, status: 200,
                                            detail: dst == nil ? "write to \(destination.label): ref + branch index (new vault there)"
                                                               : "move \(branch) on \(destination.label) (compare-and-swap)",
                                            vaultId: vaultId))
        guard result == .ok else { throw VaultError.pushConflict(branch: branch) }

        await log?.record(VaultTrafficEvent(kind: .verify, path: "sync", bytes: bytes, durationMs: start.elapsedMs,
                                            detail: "\(source.label) → \(destination.label): \(fresh.count) commits, \(sent) objects, head \(String(src.head.suffix(12)))",
                                            vaultId: vaultId))
        return VaultSyncResult(outcome: dst == nil ? .created : .fastForwarded, head: src.head,
                               commits: fresh.count, objects: sent, bytes: bytes)
    }
}
