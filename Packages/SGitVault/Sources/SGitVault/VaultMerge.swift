import CryptoKit
import Foundation

// Merging two heads of one vault (SGit Secrets, step 2: website/articles/secrets-app/, section 5.3).
//
// Two copies of a vault changed apart (two devices offline, or two iCloud versions of the vault file).
// After `VaultObjects.union` has put the other copy's objects into this store, `merge(theirs:)` joins
// the other head into a branch:
//
//   1. If the other head is already in this branch's history, nothing to do.
//   2. The merge base: the newest commit both histories share (none: an empty base).
//   3. Path by path, comparing content hashes against the base:
//        unchanged on both, or changed the same way      → as it is
//        changed on one side only                        → that side's version (a deletion included)
//        changed on one side, deleted on the other       → the change is kept: a secret is never lost
//        changed on both sides, differently              → a conflict (below)
//   4. One signed commit with both heads as parents, moved onto the branch with compare-and-swap as
//      every commit is. A copy that was simply behind is brought level the same way: history is never
//      rewritten.
//
// A conflict: the version from the side whose own latest change to that path is newer stays at the path;
// the other is kept beside it as `<name>.conflict-<8 characters of its commit id>.<ext>`, and the merge
// reports both. Why the newer change: it is most often the one meant, and every device that merges the same
// two heads picks the same winner (ties go to the larger commit id), so two devices merging independently
// arrive at the same files. Nothing is thrown away; the app shows both and the person decides.

/// One path that both sides changed differently.
public struct VaultMergeConflict: Sendable, Equatable {
    public let path: String
    /// The commit whose version stayed at `path`: the side whose latest change to it is newer.
    public let keptFrom: String
    /// Where the other side's version was kept.
    public let otherCopyPath: String
    /// The commit that made the other side's version.
    public let otherFrom: String
}

public struct VaultMergeResult: Sendable {
    public enum Kind: Sendable, Equatable {
        /// The other head was already in this branch's history.
        case upToDate
        /// A merge commit with both heads as parents.
        case merged
    }
    public let kind: Kind
    /// The branch's head afterwards.
    public let head: VaultCommit
    /// The merge base used (nil: the histories share nothing).
    public let base: String?
    /// Paths taken from the other side.
    public let takenFromTheirs: [String]
    /// Paths kept although the other side deleted them, because this side changed them (or the reverse).
    public let keptOverDeletion: [String]
    public let conflicts: [VaultMergeConflict]
}

extension SGitVault {
    /// Joins the commit `theirs` (whose objects must already be in this vault's store) into `branch`.
    /// See the notes at the top of this file for the rules.
    public func merge(theirs: String, branch: String = "current", signer: any VaultCommitSigner,
                      writeKey: SymmetricKey, accessToken: String?,
                      writer: any VaultWriteTransport) async throws -> VaultMergeResult {
        switchBranch(branch)
        let ours = try await pull()
        let theirsCommit = try await commit(theirs)

        let oursAncestors = try await ancestors(of: ours.commitId)
        if oursAncestors.contains(theirs) {
            return VaultMergeResult(kind: .upToDate, head: ours, base: theirs, takenFromTheirs: [],
                                    keptOverDeletion: [], conflicts: [])
        }
        let theirsAncestors = try await ancestors(of: theirs)
        let base = try await mergeBase(oursAncestors.intersection(theirsAncestors))
        var common = Set<String>()
        if let base { common = try await ancestors(of: base) }

        let baseFiles = try await fileMap(of: base)
        let oursFiles = try await fileMap(of: ours.commitId)
        let theirsFiles = try await fileMap(of: theirs)

        var changes: [String: Data?] = [:]
        var taken: [String] = [], keptOverDeletion: [String] = [], conflicts: [VaultMergeConflict] = []
        let paths = Set(baseFiles.keys).union(oursFiles.keys).union(theirsFiles.keys).sorted()
        for path in paths {
            let b = try await fingerprint(baseFiles[path]), o = try await fingerprint(oursFiles[path])
            let t = try await fingerprint(theirsFiles[path])
            if o == t || t == b { continue }                       // nothing new from theirs
            if o == b {                                            // only theirs changed it
                changes.updateValue(try await content(theirsFiles[path]), forKey: path)   // nil: deleted
                taken.append(path)
                continue
            }
            // Both changed it, differently.
            if t == nil { keptOverDeletion.append(path); continue }                    // ours changed, theirs deleted
            if o == nil {                                                              // theirs changed, ours deleted
                changes.updateValue(try await content(theirsFiles[path]), forKey: path)
                keptOverDeletion.append(path)
                continue
            }
            let oursChange = try await latestChange(to: path, from: ours.commitId, excluding: common)
            let theirsChange = try await latestChange(to: path, from: theirs, excluding: common)
            let theirsWins = theirsChange.timestamp > oursChange.timestamp
                || (theirsChange.timestamp == oursChange.timestamp && theirsChange.commitId > oursChange.commitId)
            let loser = theirsWins ? oursChange : theirsChange
            let otherPath = Self.conflictPath(for: path, commitId: loser.commitId)
            if theirsWins {
                changes.updateValue(try await content(theirsFiles[path]), forKey: path)
                changes.updateValue(try await content(oursFiles[path]), forKey: otherPath)
            } else {
                changes.updateValue(try await content(theirsFiles[path]), forKey: otherPath)
            }
            conflicts.append(VaultMergeConflict(path: path, keptFrom: (theirsWins ? theirsChange : oursChange).commitId,
                                                otherCopyPath: otherPath, otherFrom: loser.commitId))
        }

        var message = "Merge \(String(theirs.suffix(8))) into \(branch)"
        if !conflicts.isEmpty { message += ": \(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") kept side by side" }
        let pushed = try await commit(changes, message: VaultMerge.fit(message), branch: branch, signer: signer,
                                      writeKey: writeKey, accessToken: accessToken, writer: writer,
                                      extraParents: [theirsCommit.commitId], expectedBase: ours.commitId)
        await emit(.verify, "merge", detail: "merged \(String(theirs.suffix(12))) into \(branch): \(taken.count) taken, "
                   + "\(keptOverDeletion.count) kept over a deletion, \(conflicts.count) conflicts")
        return VaultMergeResult(kind: .merged, head: pushed.commit, base: base, takenFromTheirs: taken,
                                keptOverDeletion: keptOverDeletion, conflicts: conflicts)
    }

    /// `secrets/abc.json` → `secrets/abc.conflict-1a2b3c4d.json`; a name without an extension gets the suffix at the end.
    static func conflictPath(for path: String, commitId: String) -> String {
        let tag = ".conflict-" + String(commitId.suffix(8))
        let slash = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
        let name = path[slash...]
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            return String(path[..<dot]) + tag + String(path[dot...])
        }
        return path + tag
    }

    // MARK: History

    /// Every commit reachable from `id`, itself included.
    func ancestors(of id: String) async throws -> Set<String> {
        var seen: Set<String> = [id]
        var queue = [id]
        while let next = queue.popLast() {
            for parent in try await commit(next).parents where !seen.contains(parent) {
                seen.insert(parent)
                queue.append(parent)
            }
        }
        return seen
    }

    /// Of the shared commits, those that are not an ancestor of another shared commit; the newest of them
    /// (ties: the larger id), so that every device picks the same one.
    func mergeBase(_ shared: Set<String>) async throws -> String? {
        guard !shared.isEmpty else { return nil }
        var covered = Set<String>()
        for id in shared {
            for parent in try await commit(id).parents { covered.formUnion(try await ancestors(of: parent)) }
        }
        var best: VaultCommit?
        for id in shared.subtracting(covered) {
            let c = try await commit(id)
            if best == nil || c.timestamp > best!.timestamp || (c.timestamp == best!.timestamp && c.commitId > best!.commitId) {
                best = c
            }
        }
        return best?.commitId
    }

    /// The newest commit after the merge base (reachable from `head`, not in `excluding`) that changed `path`
    /// against its first parent. If none is found (it should be), the head itself stands for the change.
    func latestChange(to path: String, from head: String, excluding: Set<String>) async throws -> VaultCommit {
        var candidates: [VaultCommit] = []
        var seen: Set<String> = [head]
        var queue = [head]
        while let next = queue.popLast() {
            if excluding.contains(next) { continue }
            let c = try await commit(next)
            candidates.append(c)
            for parent in c.parents where !seen.contains(parent) { seen.insert(parent); queue.append(parent) }
        }
        for c in candidates.sorted(by: { $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.commitId > $1.commitId }) {
            let here = try await fingerprint(try await fileMap(of: c.commitId)[path])
            let before = try await fingerprint(try await fileMap(of: c.parents.first)[path])
            if here != before { return c }
        }
        return try await commit(head)
    }

    // MARK: Files

    func fileMap(of commitId: String?) async throws -> [String: VaultFile] {
        guard let commitId else { return [:] }
        let files = try await files(in: try await commit(commitId))
        return Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// What a file holds, for comparing: its content hash from the tree, or (an old tree without one) the
    /// hash of its decrypted bytes. Blob ids cannot be compared: each write encrypts with a fresh nonce.
    func fingerprint(_ file: VaultFile?) async throws -> String? {
        guard let file else { return nil }
        if let hash = file.contentHash { return hash }
        return VaultCrypto.contentHash(try await object(file.blobId, what: "blob \(file.path)"))
    }

    func content(_ file: VaultFile?) async throws -> Data? {
        guard let file else { return nil }
        // A large file is uploaded in parts and read to disk; merging one is not built (secrets are small).
        if file.large { throw VaultError.unsupportedFormat("merging a large file (\(file.path))") }
        return try await object(file.blobId, what: "blob \(file.path)")
    }
}

enum VaultMerge {
    /// Commit messages are kept short.
    static func fit(_ message: String) -> String { message.count <= 120 ? message : String(message.prefix(119)) + "…" }
}
