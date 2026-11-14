import CryptoKit
import Foundation
import Observation
import SGitVault

/// A server a vault can be pushed to and pulled from. Its access token is kept apart, in the Keychain.
struct VaultRemote: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var url: URL

    /// The address offered when adding a server: the only host with the write routes today.
    static let suggestedAddress = "https://dev.send.sgraph.ai"
}

/// A vault this device knows: its name, its key, and where it lives. The key is the whole credential.
struct SavedVault: Codable, Identifiable, Hashable, Sendable {
    var id: String              // the vault id
    var name: String
    var keyText: String         // sgit_private_vault_… or a read key. Secret.
    var addedAt: Date
    var createdHere: Bool
    /// The vault's objects are in a folder on this device, so it opens and takes commits with no network.
    /// False for a vault that is only read from and written to its server (as every vault was in the first builds).
    var onDevice = false
    /// The server this vault is pushed to and pulled from. Nil: it lives on this device only.
    var remoteId: String?
    /// The head commit on this device, as last seen.
    var localHead: String?
    /// The head commit this device last sent to, or fetched from, the server.
    var remoteHead: String?
    var syncedAt: Date?
    /// Why the last push did not happen, until one does.
    var pushProblem: String?

    var canWrite: Bool { VaultKey.classify(keyText) == .vault }
}

extension SavedVault {
    /// Vaults saved by the first builds with vaults (from v0.1.5, before vaults were local) have only the first five members.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        keyText = try c.decode(String.self, forKey: .keyText)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        createdHere = try c.decodeIfPresent(Bool.self, forKey: .createdHere) ?? false
        onDevice = try c.decodeIfPresent(Bool.self, forKey: .onDevice) ?? false
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        localHead = try c.decodeIfPresent(String.self, forKey: .localHead)
        remoteHead = try c.decodeIfPresent(String.self, forKey: .remoteHead)
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
        pushProblem = try c.decodeIfPresent(String.self, forKey: .pushProblem)
    }
}

/// The part of a vault's record that travels with its key: one Keychain item per vault.
struct SharedVaultRecord: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var keyText: String
    var addedAt: Date
    var remoteId: String?
}

/// The part that is true of one device only, and stays on it.
struct LocalVaultState: Codable, Equatable, Sendable {
    var createdHere = false
    var onDevice = false
    var localHead: String?
    var remoteHead: String?
    var syncedAt: Date?
    var pushProblem: String?
}

extension SavedVault {
    var shared: SharedVaultRecord { SharedVaultRecord(id: id, name: name, keyText: keyText, addedAt: addedAt, remoteId: remoteId) }
    var local: LocalVaultState {
        LocalVaultState(createdHere: createdHere, onDevice: onDevice, localHead: localHead, remoteHead: remoteHead,
                        syncedAt: syncedAt, pushProblem: pushProblem)
    }

    init(shared: SharedVaultRecord, local: LocalVaultState) {
        self.init(id: shared.id, name: shared.name, keyText: shared.keyText, addedAt: shared.addedAt,
                  createdHere: local.createdHere, onDevice: local.onDevice, remoteId: shared.remoteId,
                  localHead: local.localHead, remoteHead: local.remoteHead, syncedAt: local.syncedAt,
                  pushProblem: local.pushProblem)
    }
}

/// What a vault holds now, as the screens show it.
struct VaultContents: Equatable, Sendable {
    var head: VaultCommit
    var files: [VaultFile]
    var history: [VaultCommit]
    var branches: [VaultBranch]
}

enum VaultBookError: LocalizedError, Equatable {
    case noToken(server: String)
    case noServer
    case readOnly
    case alreadyThere
    case notOnDevice
    case badAddress

    var errorDescription: String? {
        switch self {
        case .noToken(let server): return "Writing to \(server) needs its access token. Add it to that server on the Vaults tab."
        case .noServer: return "This vault has no server. Choose one for it first."
        case .readOnly: return "This is a read key: it can open the vault but not write to it."
        case .alreadyThere: return "That vault is already in the list."
        case .notOnDevice: return "This vault is not kept on this device yet."
        case .badAddress: return "A server's address starts with https:// and names a host."
        }
    }
}

/// The vaults this device knows, and everything the app does with them. A vault is local first: it is
/// created, committed to, read and browsed in a folder on this device, with no network and no token.
/// A server is a remote: a name, an address and an access token, added when the vault should also be
/// elsewhere. Push and pull are explicit, and only ever move a server's branch forward.
///
/// Vault keys, servers and their tokens are one Keychain item each, kept on this device and, unless the
/// person turns it off, in iCloud Keychain as well, so a vault made on one device appears on the others
/// and survives losing a device (`SharedSecrets`). The key that signs this device's commits is never
/// synchronised. Every request, decryption and signature check
/// is recorded in `log`, never with key material, so the screens can show how a vault actually works.
@MainActor
@Observable
final class VaultBook {
    private let store: any SecretStore
    private let shelf: SharedSecrets
    let log = VaultTrafficLog()
    /// Where vaults on this device are kept: `<localRoot>/<vault id>/bare/…`, the layout a server holds.
    let localRoot: URL
    let cacheRoot: URL
    private let connect: @Sendable (VaultRemote) -> any VaultRemoteTransport

    private(set) var vaults: [SavedVault] = []
    private(set) var remotes: [VaultRemote] = []
    /// The ids of the servers that have a token in the Keychain.
    private(set) var remotesWithToken: Set<String> = []
    /// Whether vault keys and server tokens are kept in iCloud Keychain as well as on this device.
    private(set) var keysInICloud = true
    private(set) var busy: String?
    private(set) var problem: String?
    private(set) var notice: String?

    private var keys: [String: VaultKey] = [:]
    private var opened: [String: SGitVault] = [:]

    /// - Parameters:
    ///   - localRoot: the folder vaults on this device are kept in (Application Support, not Caches).
    ///   - connect: how a server is reached. Tests put a folder in a server's place.
    init(store: any SecretStore = KeychainStore(), localRoot: URL = VaultBook.localFolder,
         cacheRoot: URL = VaultBook.cacheFolder,
         connect: @escaping @Sendable (VaultRemote) -> any VaultRemoteTransport = { HTTPVaultTransport(server: $0.url) }) {
        self.store = store
        self.localRoot = localRoot
        self.cacheRoot = cacheRoot
        self.connect = connect
        self.shelf = SharedSecrets(store: store, prefixes: [Self.vaultPrefix, Self.serverPrefix, Self.tokenPrefix])
        adoptEarlierBuilds()
        shelf.reconcile()
        load()
    }

    static let vaultPrefix = "vault-"
    static let serverPrefix = "server-"
    static let tokenPrefix = "remote-token-"
    static let stateName = "local-vault-state"

    /// What earlier builds left in this device's Keychain, brought to the present shape. It runs before
    /// anything is read from iCloud Keychain, so it only ever touches what this device already had.
    ///
    /// - The first builds with vaults (from v0.1.5) assumed one server and kept one token, "access-token".
    ///   That becomes a named server with that token, and every vault those builds knew (all of which
    ///   exist only on that server) stays attached to it.
    /// - Builds up to the first with servers kept every vault in one item and every server in another.
    ///   Each vault and each server becomes an item of its own, and the two lists go.
    private func adoptEarlierBuilds() {
        let vaultList = store.get("vaults")
        let serverList = store.get("remotes")
        let earlierToken = store.get("access-token")
        guard vaultList != nil || serverList != nil || earlierToken != nil else { return }
        if let vaultList, let saved = try? JSONDecoder().decode([SavedVault].self, from: vaultList) { vaults = saved }
        if let serverList, let saved = try? JSONDecoder().decode([VaultRemote].self, from: serverList) { remotes = saved }

        let orphans = vaults.contains { !$0.onDevice && $0.remoteId == nil }
        if earlierToken != nil || orphans {
            let server = VaultAddress.defaultServer
            let remote: VaultRemote
            if let known = remotes.first(where: { $0.url == server }) {
                remote = known
            } else {
                remote = VaultRemote(id: Self.newRemoteId(), name: server.host() ?? "Server", url: server)
                remotes.append(remote)
            }
            if let earlierToken, shelf.get(Self.tokenName(remote.id)) == nil { shelf.set(Self.tokenName(remote.id), earlierToken) }
            for i in vaults.indices where !vaults[i].onDevice && vaults[i].remoteId == nil { vaults[i].remoteId = remote.id }
        }
        persistRemotes()
        persist()
        store.set("vaults", nil)
        store.set("remotes", nil)
        store.set("access-token", nil)
    }

    /// Reads the vaults, the servers and which servers have a token from this device's Keychain items.
    private func load() {
        var states: [String: LocalVaultState] = [:]
        if let data = store.get(Self.stateName), let saved = try? JSONDecoder().decode([String: LocalVaultState].self, from: data) {
            states = saved
        }
        vaults = shelf.names(Self.vaultPrefix)
            .compactMap { shelf.get($0) }
            .compactMap { try? JSONDecoder().decode(SharedVaultRecord.self, from: $0) }
            .map { SavedVault(shared: $0, local: states[$0.id] ?? LocalVaultState()) }
            .sorted { ($0.addedAt, $0.id) < ($1.addedAt, $1.id) }
        remotes = shelf.names(Self.serverPrefix)
            .compactMap { shelf.get($0) }
            .compactMap { try? JSONDecoder().decode(VaultRemote.self, from: $0) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        remotesWithToken = Set(remotes.map(\.id).filter { token(for: $0) != nil })
        keysInICloud = shelf.isOn
    }

    /// Looks in iCloud Keychain for vaults, servers and tokens another device made, changed or removed.
    /// Called when the Vaults screen appears.
    func refreshKeys() {
        guard busy == nil else { return }
        if shelf.reconcile() {
            load()
            for id in Array(opened.keys) where !vaults.contains(where: { $0.id == id }) { opened[id] = nil }
        }
    }

    /// Keeps vault keys and server tokens in iCloud Keychain as well (on), or on this device only (off).
    /// Turning it off takes everything onto this device first, then removes it from iCloud Keychain.
    func setKeysInICloud(_ on: Bool) {
        shelf.setOn(on)
        load()
    }

    /// Where a vault's key is kept, in words.
    func keyHome(of vault: SavedVault) -> String {
        let name = Self.vaultPrefix + vault.id
        if shelf.home(of: name) == .synchronised { return "In iCloud Keychain, on your devices" }
        if shelf.wasWithdrawn(name) { return "On this device only (removed from iCloud Keychain by another device)" }
        return "On this device only"
    }

    // MARK: What is kept

    static func newRemoteId() -> String { String(UUID().uuidString.lowercased().prefix(8)) }
    static func tokenName(_ remoteId: String) -> String { tokenPrefix + remoteId }

    private func token(for remoteId: String) -> String? {
        guard let data = shelf.get(Self.tokenName(remoteId)), let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    private static func encoded<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    /// Writes each vault's shared record to its own item (only when it changed) and this device's state
    /// of them all to one item that stays here. Removing a vault's item is `remove`'s job.
    private func persist() {
        for vault in vaults {
            guard let data = Self.encoded(vault.shared) else { continue }
            if shelf.get(Self.vaultPrefix + vault.id) != data { shelf.set(Self.vaultPrefix + vault.id, data) }
        }
        let states = Dictionary(vaults.map { ($0.id, $0.local) }, uniquingKeysWith: { first, _ in first })
        store.set(Self.stateName, Self.encoded(states))
    }

    private func persistRemotes() {
        for remote in remotes {
            guard let data = Self.encoded(remote) else { continue }
            if shelf.get(Self.serverPrefix + remote.id) != data { shelf.set(Self.serverPrefix + remote.id, data) }
        }
    }

    private func update(_ id: String, _ change: (inout SavedVault) -> Void) {
        guard let i = vaults.firstIndex(where: { $0.id == id }) else { return }
        change(&vaults[i])
        persist()
    }

    /// The vault as the book holds it now (a screen may be holding an older copy).
    func current(_ vault: SavedVault) -> SavedVault {
        vaults.first { $0.id == vault.id } ?? vault
    }

    /// The key this device signs its commits with: made once, kept in the Keychain.
    struct StoredSigner: Codable {
        var keyId: String
        var privateKey: Data
    }

    func commitSigner() throws -> SoftwareCommitSigner {
        if let data = store.get("commit-signer"), let stored = try? JSONDecoder().decode(StoredSigner.self, from: data),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: stored.privateKey) {
            return SoftwareCommitSigner(privateKey: key, keyId: stored.keyId)
        }
        let key = P256.Signing.PrivateKey()
        let made = SoftwareCommitSigner(privateKey: key)
        store.set("commit-signer", try JSONEncoder().encode(StoredSigner(keyId: made.keyId, privateKey: key.rawRepresentation)))
        return made
    }

    func clearProblem() { problem = nil }
    func clearNotice() { notice = nil }

    // MARK: Servers

    func remote(_ id: String?) -> VaultRemote? {
        guard let id else { return nil }
        return remotes.first { $0.id == id }
    }

    func hasToken(_ remote: VaultRemote) -> Bool { remotesWithToken.contains(remote.id) }

    /// Adds a server. The token may be left out: reading needs none, and it can be added later.
    @discardableResult
    func addRemote(name: String, address: String, token: String = "") -> VaultRemote? {
        problem = nil
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", let host = url.host(), !host.isEmpty else {
            problem = VaultBookError.badAddress.localizedDescription
            return nil
        }
        let label = name.trimmingCharacters(in: .whitespaces)
        let remote = VaultRemote(id: Self.newRemoteId(), name: label.isEmpty ? host : label, url: url)
        remotes.append(remote)
        persistRemotes()
        CreditLedger.shared.charge(.addServer)
        setToken(token, for: remote)
        return remote
    }

    /// Keeps, replaces or (with empty text) removes a server's access token.
    func setToken(_ text: String, for remote: VaultRemote) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        shelf.set(Self.tokenName(remote.id), trimmed.isEmpty ? nil : Data(trimmed.utf8))
        if trimmed.isEmpty { remotesWithToken.remove(remote.id) } else { remotesWithToken.insert(remote.id) }
    }

    /// The vaults that would be out of reach without this server: those not kept on this device.
    func vaultsOnlyOn(_ remote: VaultRemote) -> [SavedVault] {
        vaults.filter { $0.remoteId == remote.id && !$0.onDevice }
    }

    /// Removes a server and its token. Refused while a vault exists only there. Vaults kept on this
    /// device stay, with no server.
    func removeRemote(_ remote: VaultRemote) {
        problem = nil
        let stranded = vaultsOnlyOn(remote)
        guard stranded.isEmpty else {
            problem = "\(stranded.count == 1 ? "A vault is" : "\(stranded.count) vaults are") kept only on \(remote.name). Keep a copy on this device, or forget \(stranded.count == 1 ? "it" : "them"), before removing the server."
            return
        }
        for i in vaults.indices where vaults[i].remoteId == remote.id {
            vaults[i].remoteId = nil
            vaults[i].remoteHead = nil
            vaults[i].syncedAt = nil
            vaults[i].pushProblem = nil
        }
        persist()
        shelf.set(Self.tokenName(remote.id), nil)
        remotesWithToken.remove(remote.id)
        remotes.removeAll { $0.id == remote.id }
        shelf.set(Self.serverPrefix + remote.id, nil)
    }

    /// Chooses the server a vault on this device is pushed to, or none.
    func setRemote(_ remoteId: String?, for vault: SavedVault) {
        guard current(vault).onDevice, current(vault).remoteId != remoteId else { return }
        guard remoteId == nil || remote(remoteId) != nil else { return }
        update(vault.id) {
            $0.remoteId = remoteId
            $0.remoteHead = nil
            $0.syncedAt = nil
            $0.pushProblem = nil
        }
    }

    // MARK: Where a vault stands

    /// One honest line about where a vault is.
    static func status(of vault: SavedVault, server: String?) -> String {
        let server = server ?? "the server"
        guard vault.onDevice else {
            // Its key arrived from another device, and that device has not pushed it anywhere.
            guard vault.remoteId != nil else { return "On another of your devices only: not yet pushed to a server" }
            return "On \(server) only, not kept on this device"
        }
        guard vault.remoteId != nil else { return "On this device only" }
        if let problem = vault.pushProblem { return "Push to \(server) failed: \(problem)" }
        guard let remoteHead = vault.remoteHead else { return "On this device; not yet pushed to \(server)" }
        if remoteHead == vault.localHead {
            let when = vault.syncedAt.map { " (\($0.formatted(date: .abbreviated, time: .shortened)))" } ?? ""
            return "On this device and on \(server)\(when)"
        }
        return "Ahead of \(server): changes here have not been pushed"
    }

    func status(of vault: SavedVault) -> String {
        let now = current(vault)
        return Self.status(of: now, server: remote(now.remoteId)?.name)
    }

    // MARK: Create, add, remove

    nonisolated static var localFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "vaults", directoryHint: .isDirectory)
    }

    nonisolated static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "vaults", directoryHint: .isDirectory)
    }

    /// The folder transport for vaults on this device: each in `<localRoot>/<vault id>/`.
    private var local: FolderVaultTransport { FolderVaultTransport(root: localRoot, perVaultSubfolder: "") }

    func folder(of vaultId: String) -> URL { localRoot.appending(path: vaultId, directoryHint: .isDirectory) }

    /// Creates a new vault on this device and remembers its key. No server, no token, no network.
    func create(name: String) async {
        guard busy == nil else { return }
        problem = nil
        notice = nil
        busy = "Creating the vault"
        defer { busy = nil }
        do {
            let signer = try commitSigner()
            let writer = local
            let created = try await Task.detached(priority: .userInitiated) {
                try await VaultCreate.create(signer: signer, accessToken: nil, writer: writer)
            }.value
            keys[created.key.vaultId] = created.key
            let label = name.trimmingCharacters(in: .whitespaces)
            vaults.append(SavedVault(id: created.key.vaultId, name: label.isEmpty ? "Vault \(created.key.vaultId)" : label,
                                     keyText: created.keyText, addedAt: Date(), createdHere: true,
                                     onDevice: true, localHead: created.commitId))
            persist()
            CreditLedger.shared.charge(.createVault)
            log.record(VaultTrafficEvent(kind: .verify, path: "create", detail: "created vault \(created.key.vaultId) on this device: empty tree, one signed commit, branch current, branch index", vaultId: created.key.vaultId))
        } catch {
            problem = "The vault was not created: \(Self.describe(error))"
        }
    }

    /// Adds a vault made elsewhere, by its vault key or a read key, from the server that holds it.
    /// It is opened once to check the key. It stays on the server until a copy is kept on this device.
    func add(keyText: String, name: String, from remote: VaultRemote) async {
        guard busy == nil else { return }
        problem = nil
        notice = nil
        let text = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = "Opening the vault"
        defer { busy = nil }
        do {
            let key = try await SGitVault.deriveKey(from: text, log: log)
            guard !vaults.contains(where: { $0.id == key.vaultId }) else { throw VaultBookError.alreadyThere }
            let vault = SGitVault(address: VaultAddress(vaultId: key.vaultId, server: remote.url), readKey: key.readKey,
                                  cache: cacheRoot, log: log, transport: connect(remote))
            let head = try await vault.pull()
            keys[key.vaultId] = key
            opened[key.vaultId] = vault
            let label = name.trimmingCharacters(in: .whitespaces)
            vaults.append(SavedVault(id: key.vaultId, name: label.isEmpty ? "Vault \(key.vaultId)" : label,
                                     keyText: text, addedAt: Date(), createdHere: false,
                                     onDevice: false, remoteId: remote.id, remoteHead: head.commitId, syncedAt: Date()))
            persist()
            CreditLedger.shared.charge(.addVault)
        } catch {
            problem = "The vault was not added: \(Self.describe(error))"
        }
    }

    /// Forgets a vault on this device and deletes this device's copy of it. A copy on a server stays
    /// there; without the key nobody can open it.
    func remove(_ vault: SavedVault) {
        let now = current(vault)
        vaults.removeAll { $0.id == vault.id }
        keys[vault.id] = nil
        opened[vault.id] = nil
        shelf.set(Self.vaultPrefix + vault.id, nil)
        persist()
        if now.onDevice, VaultKey.isValidVaultId(vault.id) {
            try? FileManager.default.removeItem(at: folder(of: vault.id))
        }
    }

    // MARK: Open and read

    private func key(for vault: SavedVault) async throws -> VaultKey {
        if let key = keys[vault.id] { return key }
        let key = try await SGitVault.deriveKey(from: vault.keyText, log: log)
        keys[vault.id] = key
        return key
    }

    private func open(_ vault: SavedVault) async throws -> SGitVault {
        if let existing = opened[vault.id] { return existing }
        let now = current(vault)
        let key = try await key(for: now)
        let transport: any VaultTransport
        var server = VaultAddress.defaultServer
        if now.onDevice {
            transport = local
        } else {
            guard let remote = remote(now.remoteId) else { throw VaultBookError.noServer }
            transport = connect(remote)
            server = remote.url
        }
        let made = SGitVault(address: VaultAddress(vaultId: key.vaultId, server: server), readKey: key.readKey,
                             cache: cacheRoot, log: log, transport: transport)
        opened[vault.id] = made
        return made
    }

    func contents(of vault: SavedVault) async throws -> VaultContents {
        let handle = try await open(vault)
        await handle.switchBranch("current")
        let head = try await handle.pull()
        let files = try await handle.files().sorted { $0.path < $1.path }
        let history = try await handle.history(limit: 30)
        let branches = await handle.branches
        return VaultContents(head: head, files: files, history: history, branches: branches)
    }

    func data(of path: String, in vault: SavedVault) async throws -> Data {
        try await open(vault).read(path)
    }

    // MARK: Push and pull

    static let needsMerge = "have both changed. Bringing the two together (a merge) is not built yet, so nothing was overwritten on either side."

    /// Sends what the vault's server lacks, then moves the server's branch forward with compare-and-swap.
    /// If the server has moved on, or the two have diverged, nothing is overwritten and the vault says why.
    func push(_ vault: SavedVault) async {
        guard busy == nil else { return }
        problem = nil
        notice = nil
        let now = current(vault)
        guard now.onDevice else { problem = VaultBookError.notOnDevice.localizedDescription; return }
        guard let remote = remote(now.remoteId) else { problem = VaultBookError.noServer.localizedDescription; return }
        guard now.canWrite else { problem = VaultBookError.readOnly.localizedDescription; return }
        guard let token = token(for: remote.id) else {
            update(vault.id) { $0.pushProblem = "no access token for \(remote.name)" }
            problem = VaultBookError.noToken(server: remote.name).localizedDescription
            return
        }
        busy = "Pushing to \(remote.name)"
        defer { busy = nil }
        do {
            let key = try await key(for: now)
            let result = try await VaultSync.transfer(key: key, from: local, to: connect(remote), accessToken: token, log: log)
            switch result.outcome {
            case .upToDate, .created, .fastForwarded:
                update(vault.id) {
                    $0.localHead = result.head
                    $0.remoteHead = result.head
                    $0.syncedAt = Date()
                    $0.pushProblem = nil
                }
                if result.outcome != .upToDate { CreditLedger.shared.charge(.pushVault) }
                notice = result.outcome == .upToDate
                    ? "\(remote.name) already had everything."
                    : "Pushed \(result.commits) \(result.commits == 1 ? "commit" : "commits") to \(remote.name) (\(result.objects) objects, \(result.bytes.vaultByteString))."
            case .sourceBehind:
                update(vault.id) { $0.pushProblem = "\(remote.name) has changes this device does not have. Pull first." }
            case .diverged:
                update(vault.id) { $0.pushProblem = "this device and \(remote.name) \(Self.needsMerge)" }
            }
        } catch {
            update(vault.id) { $0.pushProblem = Self.describe(error) }
        }
    }

    /// Fetches the server's head into this device's copy, if that only moves it forward. For a vault
    /// that is not yet on this device, this is what brings it here.
    func pull(_ vault: SavedVault) async {
        guard busy == nil else { return }
        problem = nil
        notice = nil
        let now = current(vault)
        guard let remote = remote(now.remoteId) else { problem = VaultBookError.noServer.localizedDescription; return }
        busy = now.onDevice ? "Pulling from \(remote.name)" : "Copying from \(remote.name)"
        defer { busy = nil }
        do {
            let key = try await key(for: now)
            let result = try await VaultSync.transfer(key: key, from: connect(remote), to: local, accessToken: nil, log: log)
            switch result.outcome {
            case .upToDate, .created, .fastForwarded:
                update(vault.id) {
                    $0.onDevice = true
                    $0.localHead = result.head
                    $0.remoteHead = result.head
                    $0.syncedAt = Date()
                    $0.pushProblem = nil
                }
                opened[vault.id] = nil
                if result.outcome != .upToDate { CreditLedger.shared.charge(.pullVault) }
                notice = result.outcome == .upToDate
                    ? "This device already had everything on \(remote.name)."
                    : "Fetched \(result.commits) \(result.commits == 1 ? "commit" : "commits") from \(remote.name) (\(result.objects) objects, \(result.bytes.vaultByteString))."
            case .sourceBehind:
                notice = "This device is ahead of \(remote.name): there is nothing to pull."
            case .diverged:
                problem = "This device and \(remote.name) \(Self.needsMerge)"
            }
        } catch {
            problem = "Nothing was pulled: \(Self.describe(error))"
        }
    }

    // MARK: Save a debrief

    /// The files one debrief becomes in a vault. A folder is written once and never edited.
    static func files(for run: DebriefRun, audio: Data?, audioName: String?, id: String, date: Date) -> [String: Data] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let two = { (n: Int?) -> String in let v = n ?? 0; return v < 10 ? "0\(v)" : "\(v)" }
        let folder = "debriefs/\(parts.year ?? 0)/\(two(parts.month))/\(two(parts.day))/\(id)"
        var out: [String: Data] = [:]
        if let debrief = run.debrief {
            out["\(folder)/debrief.md"] = Data((debrief.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8)
        }
        if let transcript = run.transcript, !transcript.isEmpty {
            out["\(folder)/transcript.md"] = Data((transcript.timedText + "\n").utf8)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(run) { out["\(folder)/run.json"] = json }
        if let audio, let audioName {
            let ext = audioName.split(separator: ".").last.map { String($0).lowercased() } ?? "bin"
            out["\(folder)/audio.\(ext)"] = audio
        }
        return out
    }

    /// The largest audio file saved with a debrief: the vault engine does not yet do the large-object
    /// upload that sgit uses over 4 MB.
    static let largestAudio = 3_800_000

    /// Saves a debrief as one signed commit on the vault's `current` branch. Returns what was written.
    /// Into a vault on this device that needs no network and no token; pushing is a separate step.
    func save(run: DebriefRun, audioURL: URL?, to vault: SavedVault) async throws -> String {
        let now = current(vault)
        let key = try await key(for: now)
        guard let writeKey = key.writeKey else { throw VaultBookError.readOnly }
        let writer: any VaultWriteTransport
        var token: String?
        var server: VaultRemote?
        if now.onDevice {
            writer = local
        } else {
            guard let remote = remote(now.remoteId) else { throw VaultBookError.noServer }
            guard let held = self.token(for: remote.id) else { throw VaultBookError.noToken(server: remote.name) }
            writer = connect(remote)
            token = held
            server = remote
        }
        var audio: Data?
        var note = ""
        if let audioURL, let data = try? Data(contentsOf: audioURL) {
            if data.count <= Self.largestAudio { audio = data } else { note = " The audio was too large to save with it." }
        }
        let id = String(UUID().uuidString.lowercased().prefix(8))
        let files = Self.files(for: run, audio: audio, audioName: audioURL?.lastPathComponent, id: id, date: Date())
        let changes: [String: Data?] = Dictionary(uniqueKeysWithValues: files.map { ($0.key, Optional($0.value)) })
        let handle = try await open(now)
        let result = try await handle.commit(changes, message: "Debrief \(id)", branch: "current", signer: try commitSigner(),
                                           writeKey: writeKey, accessToken: token, writer: writer)
        let head = result.commit.commitId
        update(vault.id) {
            if $0.onDevice { $0.localHead = head } else { $0.remoteHead = head; $0.syncedAt = Date() }
        }
        CreditLedger.shared.charge(.saveToVault, quantity: Double(files.count))
        let bytes = result.bytesUploaded.vaultByteString
        let written = "Saved \(files.count) files in one signed commit (\(result.objectsUploaded) objects, \(bytes))"
        if let server { return "\(written) on \(server.name)." + note }
        if let remote = remote(now.remoteId) {
            return "\(written) on this device. Not yet on \(remote.name): push it from the Vaults tab." + note
        }
        return "\(written) on this device." + note
    }

    static func describe(_ error: Error) -> String {
        if let vault = error as? VaultError { return "\(vault)" }
        return error.localizedDescription
    }
}
