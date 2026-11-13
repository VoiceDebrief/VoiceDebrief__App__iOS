import CryptoKit
import Foundation

/// A native, read-only sgit vault client.
///
/// Read path (the same as sgit-ai 0.27 and `vault_read_probe.py`):
///
///     read key + vault id
///       → branch index  bare/indexes/idx-pid-muw-<HMAC(read key, branch-index domain)[:12]>
///       → named branch  (branch index entry, e.g. "current") → head_ref_id
///       → ref           bare/refs/ref-pid-muw-…        {"commit_id": "obj-cas-imm-…"}
///       → commit        bare/data/obj-cas-imm-…        {tree_id, parents, message_enc, signature, …}
///       → trees         bare/data/obj-cas-imm-…        {entries: [{name_enc, blob_id | tree_id, size_enc, …}]}
///       → blobs         bare/data/obj-cas-imm-…        (AES-GCM, optionally "\0sgz1" deflated)
///
/// Every object is checked against its content address (sha256 of the ciphertext) before it
/// is decrypted or cached. Objects are cached on disk forever; refs and the index never are.
/// Every step is written to the `VaultTrafficLog`, without key material.
public actor SGitVault {
    public nonisolated let address: VaultAddress
    public nonisolated let log: VaultTrafficLog
    public nonisolated let transportLabel: String

    let readKey: SymmetricKey
    private let structureKey: SymmetricKey
    private let structureKeyMs: Double
    let transport: any VaultTransport
    let cache: VaultObjectCache

    /// The named branch this instance reads. sgit's default is "current".
    public private(set) var branchName: String
    /// Require the head commit to carry a verified signature from a trusted key (see `trust`).
    /// An invalid signature is refused in every mode; this adds refusing unsigned, legacy and
    /// key-missing heads. Older history is still read, so vaults with unsigned legacy commits open.
    public private(set) var requireSignatures = false
    /// The author keys this reader accepts for the head commit. Nil: any key that verifies.
    public private(set) var trust: VaultTrust?

    // State of the last pull.
    public private(set) var head: VaultCommit?
    public private(set) var branches: [VaultBranch] = []
    public private(set) var format: VaultFormat?
    public private(set) var lastPull: Date?
    public private(set) var lastPullMs: Double = 0
    var fileMap: [String: VaultFile] = [:]
    private var treeRoot: VaultTreeNode?
    private var announcedKeys = false
    private var pullTask: Task<VaultCommit, Error>?

    // Immutable objects decrypted this session, kept in memory (they never change).
    private var commitMemo: [String: VaultCommit] = [:]
    var treeMemo: [String: VaultTreeNode] = [:]
    private var treeFilesMemo: [String: [VaultFile]] = [:]
    private var publicKeyMemo: [String: P256.Signing.PublicKey] = [:]

    /// The contract initialiser: reads from `address.server` over HTTPS.
    public init(address: VaultAddress, readKey: SymmetricKey, cache: URL, log: VaultTrafficLog) {
        self.init(address: address, readKey: readKey, cache: cache, log: log,
                  transport: HTTPVaultTransport(server: address.server), branch: "current")
    }

    /// Any transport (a local folder in tests), any named branch.
    public init(address: VaultAddress, readKey: SymmetricKey, cache: URL, log: VaultTrafficLog,
                transport: any VaultTransport, branch: String = "current",
                requireSignatures: Bool = false, trust: VaultTrust? = nil) {
        self.requireSignatures = requireSignatures
        self.trust = trust
        self.address = address
        self.log = log
        self.readKey = readKey
        self.transport = transport
        self.transportLabel = transport.label
        self.branchName = branch
        let start = ContinuousClock.now
        self.structureKey = VaultCrypto.structureKey(readKey: readKey)
        self.structureKeyMs = start.elapsedMs
        self.cache = VaultObjectCache(directory: cache.appending(path: address.vaultId, directoryHint: .isDirectory))
    }

    /// Open a vault from a parsed key.
    public init(key: VaultKey, server: URL = VaultAddress.defaultServer, cache: URL, log: VaultTrafficLog,
                branch: String = "current", requireSignatures: Bool = false, trust: VaultTrust? = nil) {
        self.init(address: VaultAddress(vaultId: key.vaultId, server: server), readKey: key.readKey,
                  cache: cache, log: log, transport: HTTPVaultTransport(server: server), branch: branch,
                  requireSignatures: requireSignatures, trust: trust)
    }

    // MARK: Signature policy

    /// Turn signature enforcement on or off. The next pull re-checks the head.
    public func setRequireSignatures(_ on: Bool) {
        requireSignatures = on
        head = nil
    }

    /// Replace the trusted keys. The next pull re-checks the head.
    public func setTrust(_ newTrust: VaultTrust?) {
        trust = newTrust
        head = nil
    }

    /// Trust one more author key (this device's signer, or a signer the user approved).
    public func pin(_ keyId: String) {
        var current = trust ?? VaultTrust()
        current.pinnedKeyIds.insert(keyId)
        trust = current
        head = nil
    }

    /// Parse a pasted key off the main actor, logging the derivation (never the key).
    public static func deriveKey(from text: String, log: VaultTrafficLog) async throws -> VaultKey {
        let kind = VaultKey.classify(text)
        let start = ContinuousClock.now
        let key = try await Task.detached(priority: .userInitiated) { try VaultKey.parse(text) }.value
        let detail = kind == .vault
            ? "PBKDF2-HMAC-SHA256, 600,000 rounds × 2 (read key, write key)"
            : "read key imported (\(kind?.rawValue ?? "unknown")), no derivation"
        let event = VaultTrafficEvent(kind: .keyDerivation, path: "vault key → read key", bytes: 32,
                                      durationMs: start.elapsedMs, detail: detail, vaultId: key.vaultId)
        await log.record(event)
        return key
    }

    // MARK: Contract API

    /// Fetch the ref; if the head moved, walk only trees not seen before. Blobs are fetched on `read`.
    @discardableResult
    public func pull() async throws -> VaultCommit {
        if let running = pullTask { return try await running.value }
        let task = Task { try await self.performPull() }
        pullTask = task
        defer { pullTask = nil }
        return try await task.value
    }

    public func files() async throws -> [VaultFile] {
        if head == nil { try await pull() }
        return fileMap.values.sorted { $0.path < $1.path }
    }

    public func read(_ path: String) async throws -> Data {
        if head == nil { try await pull() }
        guard let file = fileMap[path] else { throw VaultError.fileNotFound(path) }
        let data = try await object(file.blobId, what: "blob \(path)")
        let start = ContinuousClock.now
        if data.count != file.size {
            try await fail("blob \(path)", .contentMismatch(path: path, detail: "size \(data.count), tree says \(file.size)"))
        }
        if let expected = file.contentHash, VaultCrypto.contentHash(data) != expected {
            try await fail("blob \(path)", .contentMismatch(path: path, detail: "content hash differs from the tree entry"))
        }
        await emit(.verify, path, bytes: data.count, ms: start.elapsedMs,
                   detail: "size and content hash match the tree entry")
        return data
    }

    public func history(limit: Int) async throws -> [VaultCommit] {
        if head == nil { try await pull() }
        guard let head else { return [] }
        var result: [VaultCommit] = []
        var frontier: [VaultCommit] = [head]
        var seen: Set<String> = [head.commitId]
        while result.count < limit, !frontier.isEmpty {
            frontier.sort { $0.timestamp > $1.timestamp }
            let next = frontier.removeFirst()
            result.append(next)
            for parent in next.parents where !seen.contains(parent) {
                seen.insert(parent)
                let parentCommit = try await commit(parent)
                frontier.append(parentCommit)
            }
        }
        return result
    }

    // MARK: More API

    /// Read a file as UTF-8 text.
    public func readText(_ path: String) async throws -> String {
        let data = try await read(path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VaultError.malformed(path: path, detail: "not UTF-8")
        }
        return text
    }

    /// Switch to another named branch. The next `pull` reads it.
    public func switchBranch(_ name: String) {
        guard name != branchName else { return }
        branchName = name
        head = nil
        fileMap = [:]
        treeRoot = nil
    }

    /// The decrypted head tree, with sizes, for the inspector.
    public func tree() async throws -> VaultTreeNode? {
        if head == nil { try await pull() }
        return treeRoot
    }

    /// The files of any commit (not only the head), so two commits can be compared.
    public func files(in commit: VaultCommit) async throws -> [VaultFile] {
        _ = try await walkTree(commit.treeId, name: "", prefix: "")
        return (treeFilesMemo[commit.treeId] ?? []).sorted { $0.path < $1.path }
    }

    /// Fetch every blob of the head into the cache, so `read` works offline.
    public func prefetch() async throws -> Int {
        var fetched = 0
        for file in try await files() {
            _ = try await object(file.blobId, what: "blob \(file.path)")
            fetched += 1
        }
        return fetched
    }

    public func cacheStats() -> VaultCacheStats { cache.stats() }

    public func clearCache() {
        cache.clear()
        commitMemo = [:]
        treeMemo = [:]
        treeFilesMemo = [:]
        publicKeyMemo = [:]
    }

    /// Everything the debug panel shows, in one snapshot. Never contains key material.
    public func inspect(historyLimit: Int = 20) async throws -> VaultInspection {
        if head == nil { try await pull() }
        let commits = try await history(limit: historyLimit)
        let all = fileMap.values
        return VaultInspection(vaultId: address.vaultId, server: transportLabel, branch: branchName,
                               format: format, branches: branches, head: head, history: commits,
                               tree: treeRoot, fileCount: all.count, totalBytes: all.reduce(0) { $0 + $1.size },
                               cache: cache.stats(), lastPull: lastPull, lastPullMs: lastPullMs)
    }

    // MARK: Pull

    private func performPull() async throws -> VaultCommit {
        let start = ContinuousClock.now
        if !announcedKeys {
            announcedKeys = true
            await emit(.keyDerivation, "structure key", bytes: 32, ms: structureKeyMs,
                       detail: "HKDF-SHA256, info sg-vault-v1:structure-key")
        }
        let refPath = try await resolveHeadRef()
        let refData = try await fetch(refPath, cacheable: false)
        let ref: WireRef = try await decode(refData, path: refPath, what: "ref")
        guard let commitId = ref.commit_id, VaultCrypto.objectIdWidth(commitId) > 0 else {
            throw VaultError.malformed(path: refPath, detail: "no commit id")
        }
        if let head, head.commitId == commitId, treeRoot != nil {
            await emit(.verify, refPath, ms: start.elapsedMs, detail: "head unchanged (\(short(commitId)))")
            lastPull = Date()
            lastPullMs = start.elapsedMs
            return head
        }
        let commit = try await commit(commitId)
        try await enforceHeadPolicy(commit)
        let root = try await walkTree(commit.treeId, name: "", prefix: "")
        var map: [String: VaultFile] = [:]
        for file in treeFilesMemo[commit.treeId] ?? [] { map[file.path] = file }
        head = commit
        treeRoot = root
        fileMap = map
        lastPull = Date()
        lastPullMs = start.elapsedMs
        await emit(.verify, "pull", bytes: root.size, ms: lastPullMs,
                   detail: "head \(short(commitId)), \(map.count) files")
        return commit
    }

    /// Branch index → named branch → its head ref path. Falls back to the default ref.
    private func resolveHeadRef() async throws -> String {
        let indexId = VaultCrypto.branchIndexFileId(readKey: readKey, vaultId: address.vaultId)
        let indexPath = "bare/indexes/\(indexId)"
        await emit(.keyDerivation, indexPath, detail: "HMAC-SHA256 file id for the branch index")
        do {
            let data = try await fetch(indexPath, cacheable: false)
            let index: WireBranchIndex = try await decode(data, path: indexPath, what: "branch index")
            let fmt = VaultFormat(format: index.format ?? ((index.features ?? []).contains("ids-128") ? 2 : 1),
                                  minClient: index.min_client, features: index.features ?? [])
            try checkFormat(fmt)
            format = fmt
            branches = index.branches.map { b in
                VaultBranch(branchId: b.branch_id, name: b.name,
                            type: VaultBranch.BranchType(rawValue: b.branch_type ?? "") ?? .other,
                            headRefId: b.head_ref_id, publicKeyId: b.public_key_id,
                            createdAt: b.created_at.map { Date(timeIntervalSince1970: $0 / 1000) },
                            creatorBranch: b.creator_branch)
            }
            guard let branch = branches.first(where: { $0.name == branchName && $0.type == .named })
                    ?? branches.first(where: { $0.name == branchName }) else {
                throw VaultError.branchNotFound(branchName)
            }
            return "bare/refs/\(branch.headRefId)"
        } catch VaultError.notFound {
            // A vault without a branch index (older sgit): only the default ref.
            guard branchName == "current" else { throw VaultError.vaultNotFoundOrWrongKey(vaultId: address.vaultId) }
            let refPath = "bare/refs/\(VaultCrypto.refFileId(readKey: readKey, vaultId: address.vaultId))"
            await emit(.keyDerivation, refPath, detail: "HMAC-SHA256 file id for the default ref")
            do {
                _ = try await fetch(refPath, cacheable: false)
            } catch VaultError.notFound {
                try await fail(refPath, .vaultNotFoundOrWrongKey(vaultId: address.vaultId))
            }
            return refPath
        }
    }

    /// The highest sgit client version whose read path this reader implements.
    public static let compatibleClient = (0, 27, 0)
    public static let supportedFeatures: Set<String> = [
        "ids-128", "blob-deflate", "signatures-required", "long-messages", "pack-indexes",
    ]

    private func checkFormat(_ fmt: VaultFormat) throws {
        if fmt.features.contains("packs") {
            throw VaultError.unsupportedFormat("pack vault (objects stored as zips in bare/packs/)")
        }
        guard fmt.format == 1 || fmt.format == 2 else {
            throw VaultError.unsupportedFormat("format \(fmt.format)")
        }
        if let min = fmt.minClient {
            let parts = min.split(separator: ".").compactMap { Int($0) }
            if parts.count == 3 {
                let (a, b, c) = Self.compatibleClient
                if (parts[0], parts[1], parts[2]) > (a, b, c) {
                    throw VaultError.unsupportedFormat("needs sgit \(min) or newer")
                }
            }
        }
    }

    // MARK: Head policy (signatures and trusted keys)

    /// Refuse a head that is not signed by a trusted key. Called on every new head.
    private func enforceHeadPolicy(_ head: VaultCommit) async throws {
        let path = "bare/data/\(head.commitId)"
        guard requireSignatures else { return }
        guard case .verified(let keyId) = head.signature else {
            try await fail(path, .signatureRequired(commitId: head.commitId, status: head.signature.label))
        }
        guard var current = trust else { return }
        if current.pinnedKeyIds.isEmpty {
            guard current.trustOnFirstUse else {
                try await fail(path, .untrustedSigner(commitId: head.commitId, keyId: keyId))
            }
            // First open of this vault on this device: trust the keys that signed its history so far.
            current.pinnedKeyIds = try await verifiedAuthors(from: head, limit: VaultTrust.firstUseDepth)
            trust = current
            await emit(.verify, path, detail: "trust on first use: pinned \(current.pinnedKeyIds.count) signer key(s)")
            return
        }
        if current.pinnedKeyIds.contains(keyId) {
            await emit(.verify, path, detail: "signer \(keyId) is pinned")
            return
        }
        if let lister = try await trustFileListing(keyId, below: head, pinned: current.pinnedKeyIds) {
            await emit(.verify, path, detail: "signer \(keyId) is listed in \(VaultTrust.trustFile) by \(lister)")
            return
        }
        try await fail(path, .untrustedSigner(commitId: head.commitId, keyId: keyId))
    }

    /// The keys that signed the first-parent history from `head` (verified signatures only).
    private func verifiedAuthors(from head: VaultCommit, limit: Int) async throws -> Set<String> {
        var keys: Set<String> = []
        var next: VaultCommit? = head
        var seen = 0
        while let commit = next, seen < limit {
            if case .verified(let keyId) = commit.signature { keys.insert(keyId) }
            seen += 1
            next = try await firstParent(of: commit)
        }
        return keys
    }

    /// The newest commit below `head` (first parent) signed by a pinned key: does its
    /// `.vault/trusted-keys.json` list `keyId`? Returns the key that signed the listing.
    private func trustFileListing(_ keyId: String, below head: VaultCommit, pinned: Set<String>) async throws -> String? {
        var next = try await firstParent(of: head)
        var seen = 0
        while let commit = next, seen < VaultTrust.listingSearchDepth {
            if case .verified(let signer) = commit.signature, pinned.contains(signer) {
                guard let data = try await file(VaultTrust.trustFile, inTree: commit.treeId) else { return nil }
                return VaultTrust.listedKeys(in: data).contains(keyId) ? signer : nil
            }
            seen += 1
            next = try await firstParent(of: commit)
        }
        return nil
    }

    private func firstParent(of commit: VaultCommit) async throws -> VaultCommit? {
        guard let parent = commit.parents.first else { return nil }
        return try await self.commit(parent)
    }

    /// One file of a given tree (not necessarily the head's), or nil.
    private func file(_ path: String, inTree treeId: String) async throws -> Data? {
        _ = try await walkTree(treeId, name: "", prefix: "")
        guard let entry = (treeFilesMemo[treeId] ?? []).first(where: { $0.path == path }) else { return nil }
        return try await object(entry.blobId, what: "blob \(path)")
    }

    // MARK: Objects

    private func commit(_ id: String) async throws -> VaultCommit {
        if let memo = commitMemo[id] { return memo }
        let plain = try await object(id, what: "commit")
        let wire: WireCommit = try await decode(plain, path: "bare/data/\(id)", what: "commit", alreadyPlain: true)
        let message = try optionalMetadata(wire.message_enc) ?? ""
        let signature = await verifySignature(commitId: id, plaintext: plain, wire: wire)
        if case .invalid = signature {                       // never used, whatever the mode
            try await fail("bare/data/\(id)", .signatureInvalid(commitId: id))
        }
        let commit = VaultCommit(commitId: id, treeId: wire.tree_id, parents: wire.parents ?? [],
                                 message: message,
                                 timestamp: Date(timeIntervalSince1970: (wire.timestamp_ms ?? 0) / 1000),
                                 branchId: wire.branch_id, authorKeyId: wire.author_key_id,
                                 signature: signature)
        commitMemo[id] = commit
        return commit
    }

    /// Folders nested deeper than this are refused (a hostile tree cannot recurse without end).
    public static let maxTreeDepth = 64

    private func walkTree(_ id: String, name: String, prefix: String, depth: Int = 0) async throws -> VaultTreeNode {
        if let memo = treeMemo[id], memo.path == prefix + name { return memo }
        let path = "bare/data/\(id)"
        guard depth <= Self.maxTreeDepth else {
            try await fail(path, .malformed(path: path, detail: "folders nested deeper than \(Self.maxTreeDepth)"))
        }
        let plain = try await object(id, what: "tree")
        let tree: WireTree = try await decode(plain, path: path, what: "tree", alreadyPlain: true)
        var children: [VaultTreeNode] = []
        var files: [VaultFile] = []
        let here = prefix + name
        for entry in tree.entries {
            let entryName = try metadata(entry.name_enc)
            guard !entryName.isEmpty, !entryName.contains("/"), entryName != ".", entryName != ".." else {
                throw VaultError.malformed(path: path, detail: "unsafe entry name")
            }
            let entryPath = here.isEmpty ? entryName : here + "/" + entryName
            if let subtree = entry.tree_id {
                let child = try await walkTree(subtree, name: entryName, prefix: here.isEmpty ? "" : here + "/", depth: depth + 1)
                children.append(child)
                files += treeFilesMemo[subtree] ?? []
            } else if let blob = entry.blob_id {
                let sizeText = try optionalMetadata(entry.size_enc)
                let size = sizeText.flatMap { Int($0) } ?? 0
                let contentHash = try optionalMetadata(entry.content_hash_enc)
                let contentType = try optionalMetadata(entry.content_type_enc)
                let file = VaultFile(path: entryPath, size: size, blobId: blob, contentHash: contentHash,
                                     contentType: contentType, large: entry.large ?? false)
                files.append(file)
                children.append(VaultTreeNode(name: entryName, path: entryPath, objectId: blob,
                                              isFolder: false, size: size, children: []))
            }
        }
        let folderCount = children.filter(\.isFolder).count
        await emit(.decrypt, path, bytes: plain.count,
                   detail: "JSON, tree of \(tree.entries.count) entries (\(tree.entries.count - folderCount) files, \(folderCount) folders): names, sizes, hashes and types decrypted (AES-256-GCM, deterministic iv)")
        children.sort { ($0.isFolder ? 0 : 1, $0.name) < ($1.isFolder ? 0 : 1, $1.name) }
        let node = VaultTreeNode(name: name, path: here, objectId: id, isFolder: true,
                                 size: children.reduce(0) { $0 + $1.size }, children: children)
        // A subtree with the same id can sit under two paths; memoise per id for the first path only.
        treeMemo[id] = node
        treeFilesMemo[id] = files
        return node
    }

    /// Fetch (or load from cache), verify the content address, cache, decrypt.
    private func object(_ id: String, what: String) async throws -> Data {
        let width = VaultCrypto.objectIdWidth(id)
        guard width > 0 else { throw VaultError.malformed(path: id, detail: "not an obj-cas-imm id") }
        let path = "bare/data/\(id)"
        var (data, fromCache) = try await fetchWithSource(path, cacheable: true)
        var start = ContinuousClock.now
        if !VaultCrypto.objectIdMatches(id, ciphertext: data), fromCache {
            cache.remove(path)                                        // a damaged cache file: drop it and refetch
            await emit(.error, path, bytes: data.count, detail: "cached copy failed its hash check; refetching")
            (data, fromCache) = try await fetchWithSource(path, cacheable: false)
            start = ContinuousClock.now
        }
        guard VaultCrypto.objectIdMatches(id, ciphertext: data) else {
            let actual = VaultCrypto.objectId(of: data, width: width)
            try await fail(path, .integrity(objectId: id, actual: actual), bytes: data.count)
        }
        await emit(.verify, path, bytes: data.count, ms: start.elapsedMs,
                   detail: "sha256(ciphertext) matches the id (\(width) hex)")
        if !fromCache { cache.store(data, for: path) }
        return try await decrypt(data, path: path, what: what)
    }

    /// Decrypt one object, logging each step of the pipeline on the object's path:
    /// key → AES-256-GCM → inflate (deflated blobs) → JSON (in `decode`).
    func decrypt(_ data: Data, path: String, what: String) async throws -> Data {
        await emit(.keyDerivation, path, bytes: 32,
                   detail: "\(what): the vault read key (sgit has no per-object key); structure key (HKDF-SHA256 of it) as fallback")
        let magic = VaultCrypto.deflateMagic
        let deflated = data.count > magic.count + VaultCrypto.ivBytes + VaultCrypto.tagBytes && data.prefix(magic.count) == magic
        for (key, keyName) in [(readKey, "read key"), (structureKey, "structure key")] {
            let start = ContinuousClock.now
            if deflated, let packed = try? VaultCrypto.gcmOpen(data.dropFirst(magic.count), key: key) {
                await emit(.decrypt, path, bytes: packed.count, ms: start.elapsedMs,
                           detail: "\(what): AES-256-GCM, \(keyName), deflated envelope \\0sgz1, \(data.count.vaultByteString) → \(packed.count.vaultByteString)")
                let inflateStart = ContinuousClock.now
                guard let plain = Zlib.decompress(packed) else {
                    try await fail(path, .inflateFailed(path: path), bytes: packed.count)
                }
                await emit(.decrypt, path, bytes: plain.count, ms: inflateStart.elapsedMs,
                           detail: "\(what): inflate (zlib, Adler-32 checked), \(packed.count.vaultByteString) → \(plain.count.vaultByteString)")
                return plain
            }
            if let plain = try? VaultCrypto.gcmOpen(data, key: key) {
                await emit(.decrypt, path, bytes: plain.count, ms: start.elapsedMs,
                           detail: "\(what): AES-256-GCM, \(keyName), iv 12 B + tag 16 B, \(data.count.vaultByteString) → \(plain.count.vaultByteString)")
                return plain
            }
        }
        try await fail(path, .decryptFailed(path: path), bytes: data.count)
    }

    func decode<T: Decodable>(_ data: Data, path: String, what: String, alreadyPlain: Bool = false) async throws -> T {
        let plain = alreadyPlain ? data : try await decrypt(data, path: path, what: what)
        let start = ContinuousClock.now
        do {
            let value = try JSONDecoder().decode(T.self, from: plain)
            await emit(.decrypt, path, bytes: plain.count, ms: start.elapsedMs,
                       detail: "JSON, \(what) parsed, \(plain.count.vaultByteString)")
            return value
        } catch {
            try await fail(path, .malformed(path: path, detail: "\(what) JSON has an unexpected shape"))
        }
    }

    private func optionalMetadata(_ base64: String?) throws -> String? {
        guard let base64 else { return nil }
        return try metadata(base64)
    }

    private func metadata(_ base64: String) throws -> String {
        try VaultCrypto.openMetadata(base64, readKey: readKey, structureKey: structureKey)
    }

    // MARK: Signatures

    private func verifySignature(commitId: String, plaintext: Data, wire: WireCommit) async -> VaultSignatureStatus {
        guard let signature = wire.signature, !signature.isEmpty else { return .unsigned }
        guard let keyId = wire.author_key_id, !keyId.isEmpty else { return .legacy }
        let path = "bare/data/\(commitId)"
        let start = ContinuousClock.now
        let publicKey: P256.Signing.PublicKey
        if let memo = publicKeyMemo[keyId] {
            publicKey = memo
        } else {
            do {
                let keyPath = "bare/keys/\(keyId)"
                let data = try await fetch(keyPath, cacheable: true)
                let wireKey: WirePublicKey = try await decode(data, path: keyPath, what: "public key")
                publicKey = try P256.Signing.PublicKey(pemRepresentation: wireKey.pem)
                publicKeyMemo[keyId] = publicKey
            } catch {
                await emit(.verify, path, ms: start.elapsedMs, detail: "signature not checked: key \(keyId) unavailable")
                return .keyMissing(keyId: keyId)
            }
        }
        guard let raw = Data(base64Encoded: signature),
              let sig = try? P256.Signing.ECDSASignature(rawRepresentation: raw),
              let bytes = try? CanonicalJSON.signingBytes(commitJSON: plaintext),
              publicKey.isValidSignature(sig, for: bytes) else {
            await emit(.error, path, ms: start.elapsedMs, detail: "ECDSA P-256 signature does NOT verify (key \(keyId))")
            return .invalid(keyId: keyId)
        }
        await emit(.verify, path, bytes: raw.count, ms: start.elapsedMs,
                   detail: "ECDSA P-256 signature verified (key \(keyId))")
        return .verified(keyId: keyId)
    }

    // MARK: Transport and logging

    func fetch(_ path: String, cacheable: Bool) async throws -> Data {
        try await fetchWithSource(path, cacheable: cacheable).0
    }

    private func fetchWithSource(_ path: String, cacheable: Bool) async throws -> (Data, Bool) {
        if cacheable, let data = cache.load(path) {
            await emit(.cacheHit, path, bytes: data.count, detail: "on-disk object cache")
            return (data, true)
        }
        let start = ContinuousClock.now
        let response: VaultResponse
        do {
            response = try await transport.get(vaultId: address.vaultId, path: path)
        } catch {
            await emit(.error, path, ms: start.elapsedMs, detail: "network: \(error.localizedDescription)")
            throw error
        }
        await emit(.request, path, bytes: response.data.count, ms: start.elapsedMs, status: response.status,
                   detail: "GET \(transportLabel)\(cacheable ? "" : ", not cached (mutable)")")
        switch response.status {
        case 200: return (response.data, false)
        case 404: throw VaultError.notFound(path: path)
        default: try await fail(path, .http(status: response.status, path: path))
        }
    }

    func emit(_ kind: VaultTrafficEvent.Kind, _ path: String, bytes: Int = 0, ms: Double = 0,
                      status: Int? = nil, detail: String = "") async {
        let event = VaultTrafficEvent(kind: kind, path: path, bytes: bytes, durationMs: ms, status: status,
                                      detail: detail, vaultId: address.vaultId)
        await log.record(event)
    }

    /// Log the error, then throw it.
    func fail(_ path: String, _ error: VaultError, bytes: Int = 0) async throws -> Never {
        await emit(.error, path, bytes: bytes, detail: error.description)
        throw error
    }

    private func short(_ id: String) -> String { String(id.suffix(12)) }
}

/// Everything the debug panel's vault inspector shows. No key material.
public struct VaultInspection: Sendable {
    public let vaultId: String
    public let server: String
    public let branch: String
    public let format: VaultFormat?
    public let branches: [VaultBranch]
    public let head: VaultCommit?
    public let history: [VaultCommit]
    public let tree: VaultTreeNode?
    public let fileCount: Int
    public let totalBytes: Int
    public let cache: VaultCacheStats
    public let lastPull: Date?
    public let lastPullMs: Double
}

extension ContinuousClock.Instant {
    var elapsedMs: Double {
        let d = self.duration(to: .now)
        return Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15
    }
}
