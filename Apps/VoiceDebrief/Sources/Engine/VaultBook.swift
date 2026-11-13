import CryptoKit
import Foundation
import Observation
import SGitVault

/// A vault this device knows: its name and its key. The key is the whole credential.
struct SavedVault: Codable, Identifiable, Hashable, Sendable {
    var id: String              // the vault id
    var name: String
    var keyText: String         // sgit_private_vault_… or a read key. Secret.
    var addedAt: Date
    var createdHere: Bool

    var canWrite: Bool { VaultKey.classify(keyText) == .vault }
}

/// What a vault holds now, as the screens show it.
struct VaultContents: Equatable, Sendable {
    var head: VaultCommit
    var files: [VaultFile]
    var history: [VaultCommit]
    var branches: [VaultBranch]
}

enum VaultBookError: LocalizedError {
    case noToken
    case readOnly
    case alreadyThere

    var errorDescription: String? {
        switch self {
        case .noToken: return "Writing to a vault needs an SG/Send access token. Add one on the Vaults tab."
        case .readOnly: return "This is a read key: it can open the vault but not write to it."
        case .alreadyThere: return "That vault is already in the list."
        }
    }
}

/// The vaults this device knows, and everything the app does with them: create, add, open, read,
/// and save a debrief. Keys and the access token live in the Keychain. Every request, decryption
/// and signature check is recorded in `log`, never with key material, so the screens can show how
/// a vault actually works.
@MainActor
@Observable
final class VaultBook {
    private let store: any SecretStore
    let log = VaultTrafficLog()
    let server = VaultAddress.defaultServer

    private(set) var vaults: [SavedVault] = []
    private(set) var hasToken = false
    private(set) var busy: String?
    private(set) var problem: String?

    private var keys: [String: VaultKey] = [:]
    private var opened: [String: SGitVault] = [:]

    init(store: any SecretStore = KeychainStore()) {
        self.store = store
        if let data = store.get("vaults"), let saved = try? JSONDecoder().decode([SavedVault].self, from: data) {
            vaults = saved
        }
        hasToken = token != nil
    }

    // MARK: What is kept

    private var token: String? {
        guard let data = store.get("access-token"), let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    func setToken(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.set("access-token", trimmed.isEmpty ? nil : Data(trimmed.utf8))
        hasToken = token != nil
    }

    private func persist() {
        store.set("vaults", try? JSONEncoder().encode(vaults))
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

    // MARK: Create, add, remove

    func clearProblem() { problem = nil }

    /// Creates a new vault on the server and remembers its key.
    func create(name: String) async {
        guard busy == nil else { return }
        problem = nil
        guard let token else { problem = VaultBookError.noToken.localizedDescription; return }
        busy = "Creating the vault"
        defer { busy = nil }
        do {
            let signer = try commitSigner()
            let writer = HTTPVaultTransport(server: server)
            let created = try await Task.detached(priority: .userInitiated) {
                try await VaultCreate.create(signer: signer, accessToken: token, writer: writer)
            }.value
            keys[created.key.vaultId] = created.key
            let label = name.trimmingCharacters(in: .whitespaces)
            vaults.append(SavedVault(id: created.key.vaultId, name: label.isEmpty ? "Vault \(created.key.vaultId)" : label,
                                     keyText: created.keyText, addedAt: Date(), createdHere: true))
            persist()
            log.record(VaultTrafficEvent(kind: .verify, path: "create", detail: "created vault \(created.key.vaultId): empty tree, one signed commit, branch current, branch index", vaultId: created.key.vaultId))
        } catch {
            problem = "The vault was not created: \(Self.describe(error))"
        }
    }

    /// Adds a vault made elsewhere, by its vault key or a read key. It is opened once to check the key.
    func add(keyText: String, name: String) async {
        guard busy == nil else { return }
        problem = nil
        let text = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = "Opening the vault"
        defer { busy = nil }
        do {
            let key = try await SGitVault.deriveKey(from: text, log: log)
            guard !vaults.contains(where: { $0.id == key.vaultId }) else { throw VaultBookError.alreadyThere }
            let vault = SGitVault(key: key, server: server, cache: Self.cacheFolder, log: log)
            _ = try await vault.pull()
            keys[key.vaultId] = key
            opened[key.vaultId] = vault
            let label = name.trimmingCharacters(in: .whitespaces)
            vaults.append(SavedVault(id: key.vaultId, name: label.isEmpty ? "Vault \(key.vaultId)" : label,
                                     keyText: text, addedAt: Date(), createdHere: false))
            persist()
        } catch {
            problem = "The vault was not added: \(Self.describe(error))"
        }
    }

    /// Forgets a vault on this device. The vault itself stays on the server; without its key nobody can open it.
    func remove(_ vault: SavedVault) {
        vaults.removeAll { $0.id == vault.id }
        keys[vault.id] = nil
        opened[vault.id] = nil
        persist()
    }

    // MARK: Open and read

    static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "vaults", directoryHint: .isDirectory)
    }

    private func key(for vault: SavedVault) async throws -> VaultKey {
        if let key = keys[vault.id] { return key }
        let key = try await SGitVault.deriveKey(from: vault.keyText, log: log)
        keys[vault.id] = key
        return key
    }

    private func open(_ vault: SavedVault) async throws -> SGitVault {
        if let existing = opened[vault.id] { return existing }
        let made = SGitVault(key: try await key(for: vault), server: server, cache: Self.cacheFolder, log: log)
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
    func save(run: DebriefRun, audioURL: URL?, to vault: SavedVault) async throws -> String {
        guard let token else { throw VaultBookError.noToken }
        let key = try await key(for: vault)
        guard let writeKey = key.writeKey else { throw VaultBookError.readOnly }
        var audio: Data?
        var note = ""
        if let audioURL, let data = try? Data(contentsOf: audioURL) {
            if data.count <= Self.largestAudio { audio = data } else { note = " The audio was too large to save with it." }
        }
        let id = String(UUID().uuidString.lowercased().prefix(8))
        let files = Self.files(for: run, audio: audio, audioName: audioURL?.lastPathComponent, id: id, date: Date())
        let changes: [String: Data?] = Dictionary(uniqueKeysWithValues: files.map { ($0.key, Optional($0.value)) })
        let handle = try await open(vault)
        let result = try await handle.commit(changes, message: "Debrief \(id)", branch: "current", signer: try commitSigner(),
                                           writeKey: writeKey, accessToken: token, writer: HTTPVaultTransport(server: server))
        let bytes = result.bytesUploaded.vaultByteString
        return "Saved \(files.count) files in one signed commit (\(result.objectsUploaded) objects, \(bytes))." + note
    }

    static func describe(_ error: Error) -> String {
        if let vault = error as? VaultError { return "\(vault)" }
        return error.localizedDescription
    }
}
