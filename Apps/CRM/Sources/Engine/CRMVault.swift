import CryptoKit
import Foundation
import Observation
import SGitVault

/// The user's CRM: one sgit vault, kept on this device first (a vault is local first; a server is a
/// remote, later), holding the records in the `sgit.ai/crm/v1` format. Its key and the key that signs
/// its commits are in the Keychain. Also opens other vaults, read only, to import from.
@MainActor
@Observable
final class CRMVault {
    enum Problem: LocalizedError {
        case noVault
        case readOnly

        var errorDescription: String? {
            switch self {
            case .noVault: return "There is no CRM vault on this device yet."
            case .readOnly: return "This key can read the vault but not change it."
            }
        }
    }

    private let store: any SecretStore
    /// Where the CRM vault lives on this device, in the server's layout.
    let localRoot: URL
    let cacheRoot: URL
    /// Where other vaults are read from: the vault server, or a folder in tests.
    let remote: any VaultTransport
    let log = VaultTrafficLog()

    private(set) var vaultID: String?
    private(set) var people: [Person] = []
    private(set) var organisations: [Organisation] = []
    private(set) var interactions: [Interaction] = []
    private(set) var introductions: [Introduction] = []
    private(set) var followUps: [FollowUp] = []
    private(set) var drafts: [Draft] = []
    private(set) var plays: [Play] = []
    /// Files in the vault that are not valid records, with why: shown, never dropped.
    private(set) var unreadable: [ImportScanner.Skipped] = []
    private(set) var commits: Int = 0

    private var key: VaultKey?
    private var handle: SGitVault?

    static let keyName = "crm-vault-key"
    static let signerName = "crm-commit-signer"

    init(store: any SecretStore = KeychainStore(), root: URL? = nil,
         remote: any VaultTransport = HTTPVaultTransport()) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "CRM", directoryHint: .isDirectory)
        self.store = store
        self.localRoot = base.appending(path: "vaults", directoryHint: .isDirectory)
        self.cacheRoot = base.appending(path: "cache", directoryHint: .isDirectory)
        self.remote = remote
    }

    var local: FolderVaultTransport { FolderVaultTransport(root: localRoot, perVaultSubfolder: "") }
    var hasVault: Bool { store.get(Self.keyName) != nil }

    // MARK: Keys

    struct StoredSigner: Codable {
        var keyId: String
        var privateKey: Data
    }

    func commitSigner() throws -> SoftwareCommitSigner {
        if let data = store.get(Self.signerName), let stored = try? JSONDecoder().decode(StoredSigner.self, from: data),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: stored.privateKey) {
            return SoftwareCommitSigner(privateKey: key, keyId: stored.keyId)
        }
        let key = P256.Signing.PrivateKey()
        let made = SoftwareCommitSigner(privateKey: key)
        store.set(Self.signerName, try JSONEncoder().encode(StoredSigner(keyId: made.keyId, privateKey: key.rawRepresentation)))
        return made
    }

    /// The fingerprint of this device's signing key: what a record names as the key that changed it.
    var signerFingerprint: String? {
        guard let signer = try? commitSigner() else { return nil }
        return SGitVault.fingerprint(of: signer)
    }

    // MARK: The CRM vault

    /// Opens the CRM vault, making it on this device the first time. No server, no network.
    func open() async throws {
        if handle != nil { return }
        let key: VaultKey
        if let data = store.get(Self.keyName), let text = String(data: data, encoding: .utf8) {
            key = try await SGitVault.deriveKey(from: text, log: log)
        } else {
            let signer = try commitSigner()
            let writer = local
            try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
            let created = try await Task.detached(priority: .userInitiated) {
                try await VaultCreate.create(signer: signer, accessToken: nil, writer: writer, message: "SGit CRM vault created")
            }.value
            store.set(Self.keyName, Data(created.keyText.utf8))
            key = created.key
        }
        self.key = key
        vaultID = key.vaultId
        handle = SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: cacheRoot, log: log,
                           transport: local, branch: "current")
        try await reload()
    }

    /// Reads every record file in the vault.
    func reload() async throws {
        guard let handle else { throw Problem.noVault }
        _ = try await handle.pull()
        let files = try await handle.files()
        var found: [AnyRecord] = []
        var bad: [ImportScanner.Skipped] = []
        for file in files where RecordFiles.parse(path: file.path) != nil {
            do {
                found.append(try RecordFiles.decode(path: file.path, data: try await handle.read(file.path)))
            } catch {
                bad.append(ImportScanner.Skipped(path: file.path, reason: error.localizedDescription))
            }
        }
        apply(found)
        unreadable = bad
        commits = (try? await handle.history(limit: 1000).count) ?? 0
    }

    private func apply(_ records: [AnyRecord]) {
        var p: [Person] = [], o: [Organisation] = [], i: [Interaction] = [], n: [Introduction] = []
        var f: [FollowUp] = [], d: [Draft] = [], y: [Play] = []
        for r in records {
            switch r {
            case .person(let x): p.append(x)
            case .organisation(let x): o.append(x)
            case .interaction(let x): i.append(x)
            case .introduction(let x): n.append(x)
            case .followUp(let x): f.append(x)
            case .draft(let x): d.append(x)
            case .play(let x): y.append(x)
            }
        }
        people = p.sorted { $0.name.value.localizedCaseInsensitiveCompare($1.name.value) == .orderedAscending }
        organisations = o.sorted { $0.name.value.localizedCaseInsensitiveCompare($1.name.value) == .orderedAscending }
        interactions = i.sorted { $0.at > $1.at }
        introductions = n
        followUps = f
        drafts = d
        plays = y
    }

    /// Writes a plan's records as one signed commit, then reads the vault again.
    @discardableResult
    func commit(_ plan: ImportPlanner.Plan, message: String) async throws -> String {
        try await commit(records: plan.records, message: message)
    }

    /// Writes records as one signed commit, then reads the vault again.
    @discardableResult
    func commit(records: [AnyRecord], message: String) async throws -> String {
        guard let handle, let key else { throw Problem.noVault }
        guard let writeKey = key.writeKey else { throw Problem.readOnly }
        let files = try RecordFiles.files(records)
        let changes: [String: Data?] = files.mapValues { Optional($0) }
        let result = try await handle.commit(changes, message: message, branch: "current", signer: try commitSigner(),
                                             writeKey: writeKey, accessToken: nil, writer: local)
        try await reload()
        return result.commit.commitId
    }

    /// Fills an empty vault with the invented sample records, in one commit. Only for the sample vault.
    func seedSampleIfEmpty(name: String) async throws {
        guard people.isEmpty, organisations.isEmpty else { return }
        try await commit(records: SampleData.records(now: Date(), by: actor(name: name.isEmpty ? "Me" : name)),
                         message: "Sample data: invented people from \(SampleData.event)")
    }

    /// Where the sample vault lives, apart from the real one.
    static var sampleRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "CRM-sample", directoryHint: .isDirectory)
    }

    /// Who this device is when it changes a record: the person using it, named by its signing key.
    func actor(name: String) -> Actor {
        Actor.person(name.isEmpty ? "Me" : name, key: signerFingerprint)
    }

    /// One file of another vault, read by its key: the agents' report, for example.
    func read(path: String, keyText: String) async throws -> Data {
        let key = try await SGitVault.deriveKey(from: keyText.trimmingCharacters(in: .whitespacesAndNewlines), log: log)
        let vault = SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: cacheRoot, log: log,
                              transport: remote, branch: "current")
        _ = try await vault.pull()
        return try await vault.read(path)
    }

    // MARK: Other vaults, to import from

    /// The files of another vault that the import can read, by its key (a vault key or a read key).
    /// Files larger than `maxBytes` are left out.
    func importableFiles(keyText: String, maxBytes: Int = 15_000_000) async throws -> (vault: String, files: [(path: String, data: Data)]) {
        let key = try await SGitVault.deriveKey(from: keyText.trimmingCharacters(in: .whitespacesAndNewlines), log: log)
        let vault = SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: cacheRoot, log: log,
                              transport: remote, branch: "current")
        _ = try await vault.pull()
        var out: [(path: String, data: Data)] = []
        for file in try await vault.files() where ImportScanner.kind(of: file.path) != nil && file.size <= maxBytes {
            out.append((file.path, try await vault.read(file.path)))
        }
        return (key.vaultId, out)
    }
}
