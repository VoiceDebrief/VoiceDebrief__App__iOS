import CryptoKit
import Foundation
import ImageIO
import Observation
import SGitVault
import UIKit
import UniformTypeIdentifiers

// Started from Apps/VoiceDebrief/Sources/Engine/VaultBook.swift (v0.1.8): the saved vaults, the token,
// the signing key, create, add and open are the same. What a debrief needed is gone; files, thumbnails,
// delete, rename and what a commit changed are new. Shared app code moves into a package later.

/// A vault this device knows: its name and its key. The key is the whole credential.
struct SavedVault: Codable, Identifiable, Hashable, Sendable {
    var id: String              // the vault id
    var name: String
    var keyText: String         // a vault key or a read key. Secret.
    var addedAt: Date
    var createdHere: Bool
    /// The vault's objects are in a folder on this device and nowhere else: it opens and takes commits
    /// with no network and no token. False once it has been sent to the server, or for a vault that was
    /// added by its key: those are read from and written to the server.
    var onDevice = false

    var canWrite: Bool { VaultKey.classify(keyText) == .vault }
}

extension SavedVault {
    /// Vaults saved by the first build have no `onDevice`: they were all on the server.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        keyText = try c.decode(String.self, forKey: .keyText)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        createdHere = try c.decodeIfPresent(Bool.self, forKey: .createdHere) ?? false
        onDevice = try c.decodeIfPresent(Bool.self, forKey: .onDevice) ?? false
    }
}

/// What a vault holds now, as the screens show it.
struct VaultContents: Equatable, Sendable {
    var head: VaultCommit
    var files: [VaultFile]
    var history: [VaultCommit]
    var branches: [VaultBranch]
}

enum VaultShelfError: LocalizedError {
    case noToken
    case readOnly
    case alreadyThere
    case nameTaken(String)
    case filesOnTheirWay
    case serverDiffers

    var errorDescription: String? {
        switch self {
        case .noToken: return "The server takes changes only from people it knows, so writing to it needs an access key. Add one in Settings."
        case .readOnly: return "This is a read key: it can open the vault but not change it."
        case .alreadyThere: return "That vault is already in the list."
        case .nameTaken(let name): return "There is already a file called \(name) in this folder."
        case .filesOnTheirWay: return "Files are still on their way into this vault. Send it to the server when they are in."
        case .serverDiffers: return "The server already holds this vault with changes this device does not have, so nothing was sent."
        }
    }
}

/// Lets a few pieces of work run at once and makes the rest wait their turn.
actor Limiter {
    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { free = count }

    func acquire() async {
        if free > 0 {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty { free += 1 } else { waiting.removeFirst().resume() }
    }
}

enum Thumbnail {
    /// A small JPEG of an image file, made without decoding the image at full size.
    static func jpeg(of url: URL, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}

/// The vaults this device knows, and everything the app reads from them or changes in them one file
/// at a time. Adding files is the `Outbox`. Keys and the access key live in the Keychain. Every
/// request, decryption and signature check is recorded in `log`, never with key material.
@MainActor
@Observable
final class VaultShelf {
    private let store: any SecretStore
    let log = VaultTrafficLog()
    let server: URL
    /// The server: where a vault that is not on this device is read from and written to. A folder in tests.
    let transport: any VaultFileTransport
    let cacheRoot: URL
    /// Where vaults that live on this device are kept, each in `<localRoot>/<vault id>/`, in the server's layout.
    let localRoot: URL
    var local: FolderVaultTransport { FolderVaultTransport(root: localRoot, perVaultSubfolder: "") }

    private(set) var vaults: [SavedVault] = []
    private(set) var hasToken = false
    private(set) var busy: String?
    private(set) var problem: String?
    /// The latest contents read for each vault, by vault id.
    private(set) var contents: [String: VaultContents] = [:]
    /// Bytes received so far for a file being fetched, by blob id.
    private(set) var fetchedBytes: [String: Int] = [:]

    private var keys: [String: VaultKey] = [:]
    private var opened: [String: SGitVault] = [:]
    private var fetching: [String: Task<URL, Error>] = [:]
    private let thumbnails = Limiter(3)

    init(store: any SecretStore = KeychainStore(), server: URL = VaultAddress.defaultServer,
         transport: (any VaultFileTransport)? = nil, cacheRoot: URL? = nil, localRoot: URL? = nil) {
        self.store = store
        self.server = server
        self.transport = transport ?? HTTPVaultTransport(server: server)
        self.cacheRoot = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.localRoot = localRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "vaults", directoryHint: .isDirectory)
        if let data = store.get("vaults"), let saved = try? JSONDecoder().decode([SavedVault].self, from: data) {
            vaults = saved
        }
        hasToken = token != nil
    }

    // MARK: What is kept

    var token: String? {
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

    /// The key this device signs its commits with: made once, kept in the Keychain, never sent anywhere.
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

    /// This device's signing key, as the history shows a signer: its fingerprint.
    var deviceFingerprint: String? {
        guard let signer = try? commitSigner() else { return nil }
        return SGitVault.fingerprint(of: signer)
    }

    // MARK: Create, add, remove

    func clearProblem() { problem = nil }

    private func label(_ name: String, _ vaultId: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Vault \(vaultId)" : trimmed
    }

    /// The saved vault as it is now. Screens hold a copy from when they opened; this is the current one.
    func current(_ vault: SavedVault) -> SavedVault {
        vaults.first { $0.id == vault.id } ?? vault
    }

    /// Where this vault is read from and written to now: its folder on this device, or the server.
    func transport(for vault: SavedVault) -> any VaultFileTransport {
        current(vault).onDevice ? local : transport
    }

    /// Whether writing to the server needs a token that is not there.
    private var serverNeedsToken: Bool { token == nil && transport is HTTPVaultTransport }

    /// Creates a new vault on this device and remembers its key. No server, no token, no network.
    @discardableResult
    func create(name: String) async -> SavedVault? {
        guard busy == nil else { return nil }
        problem = nil
        busy = "Creating the vault"
        defer { busy = nil }
        do {
            let signer = try commitSigner()
            let writer = local
            let created = try await Task.detached(priority: .userInitiated) {
                try await VaultCreate.create(signer: signer, accessToken: nil, writer: writer)
            }.value
            keys[created.key.vaultId] = created.key
            let saved = SavedVault(id: created.key.vaultId, name: label(name, created.key.vaultId),
                                   keyText: created.keyText, addedAt: Date(), createdHere: true, onDevice: true)
            vaults.append(saved)
            persist()
            log.record(VaultTrafficEvent(kind: .verify, path: "create",
                                         detail: "created vault \(created.key.vaultId) on this device: empty tree, one signed commit, branch current, branch index",
                                         vaultId: created.key.vaultId))
            return saved
        } catch {
            problem = "The vault was not created: \(Self.describe(error))"
            return nil
        }
    }

    /// Sends a vault that lives on this device to the server, large files included, so that somebody
    /// else can open it. From then on the server is where it lives: this device reads and writes it
    /// there, and its folder here is removed. Nothing is removed unless everything arrived.
    /// - Parameter pending: whether files are still on their way into the vault.
    @discardableResult
    func sendToServer(_ vault: SavedVault, pending: Bool = false) async -> Bool {
        guard busy == nil else { return false }
        problem = nil
        let now = current(vault)
        guard now.onDevice else { return true }
        guard now.canWrite else { problem = VaultShelfError.readOnly.localizedDescription; return false }
        guard !pending else { problem = VaultShelfError.filesOnTheirWay.localizedDescription; return false }
        guard !serverNeedsToken else { problem = VaultShelfError.noToken.localizedDescription; return false }
        busy = "Sending the vault to \(serverName)"
        defer { busy = nil }
        do {
            let key = try await key(for: now)
            let result = try await VaultSync.transferWithLargeFiles(key: key, from: local, to: transport, accessToken: token,
                                                                    scratch: scratchFolder, log: log)
            switch result.outcome {
            case .created, .fastForwarded, .upToDate:
                guard let index = vaults.firstIndex(where: { $0.id == vault.id }) else { return false }
                vaults[index].onDevice = false
                persist()
                opened[vault.id] = nil
                try? FileManager.default.removeItem(at: localRoot.appending(path: vault.id, directoryHint: .isDirectory))
                _ = try? await load(vaults[index])
                return true
            case .sourceBehind, .diverged:
                problem = VaultShelfError.serverDiffers.localizedDescription
                return false
            }
        } catch {
            problem = "The vault was not sent: \(Self.describe(error))"
            return false
        }
    }

    var serverName: String { server.host() ?? "the server" }

    /// Adds a vault made elsewhere, by its vault key, a read key, or a web Vault link. It is opened once
    /// to check the key.
    @discardableResult
    func add(keyText: String, name: String) async -> SavedVault? {
        guard busy == nil else { return nil }
        problem = nil
        let text = VaultNaming.keyText(from: keyText)
        busy = "Opening the vault"
        defer { busy = nil }
        do {
            let key = try await SGitVault.deriveKey(from: text, log: log)
            guard !vaults.contains(where: { $0.id == key.vaultId }) else { throw VaultShelfError.alreadyThere }
            let vault = makeHandle(key, onDevice: false)
            _ = try await vault.pull()
            keys[key.vaultId] = key
            opened[key.vaultId] = vault
            let saved = SavedVault(id: key.vaultId, name: label(name, key.vaultId), keyText: text,
                                   addedAt: Date(), createdHere: false)
            vaults.append(saved)
            persist()
            return saved
        } catch {
            problem = "The vault was not added: \(Self.describe(error))"
            return nil
        }
    }

    func rename(_ vault: SavedVault, to name: String) {
        guard let index = vaults.firstIndex(where: { $0.id == vault.id }) else { return }
        vaults[index].name = label(name, vault.id)
        persist()
    }

    /// Forgets a vault on this device. The vault itself stays where it is; without its key nobody can open it.
    func remove(_ vault: SavedVault) {
        vaults.removeAll { $0.id == vault.id }
        keys[vault.id] = nil
        opened[vault.id] = nil
        contents[vault.id] = nil
        try? FileManager.default.removeItem(at: filesFolder.appending(path: vault.id, directoryHint: .isDirectory))
        // A vault that lives only on this device goes with it: the screen says so before asking.
        try? FileManager.default.removeItem(at: localRoot.appending(path: vault.id, directoryHint: .isDirectory))
        persist()
    }

    // MARK: Open and read

    var objectCache: URL { cacheRoot.appending(path: "vault-objects", directoryHint: .isDirectory) }
    var filesFolder: URL { cacheRoot.appending(path: "vault-files", directoryHint: .isDirectory) }
    var thumbnailFolder: URL { cacheRoot.appending(path: "vault-thumbnails", directoryHint: .isDirectory) }
    var scratchFolder: URL { cacheRoot.appending(path: "vault-scratch", directoryHint: .isDirectory) }

    private func makeHandle(_ key: VaultKey, onDevice: Bool) -> SGitVault {
        let place: any VaultTransport = onDevice ? local : transport
        return SGitVault(address: VaultAddress(vaultId: key.vaultId, server: server), readKey: key.readKey,
                         cache: objectCache, log: log, transport: place, branch: "current")
    }

    func key(for vault: SavedVault) async throws -> VaultKey {
        if let key = keys[vault.id] { return key }
        let key = try await SGitVault.deriveKey(from: vault.keyText, log: log)
        keys[vault.id] = key
        return key
    }

    func open(_ vault: SavedVault) async throws -> SGitVault {
        if let existing = opened[vault.id] { return existing }
        let now = current(vault)
        let made = makeHandle(try await key(for: now), onDevice: now.onDevice)
        opened[vault.id] = made
        return made
    }

    /// Fetches the latest head, files and history. The result is also kept in `contents`.
    @discardableResult
    func load(_ vault: SavedVault) async throws -> VaultContents {
        let handle = try await open(vault)
        await handle.switchBranch("current")
        let head = try await handle.pull()
        let files = try await handle.files()
        let history = try await handle.history(limit: 50)
        let branches = await handle.branches
        let read = VaultContents(head: head, files: files, history: history, branches: branches)
        contents[vault.id] = read
        return read
    }

    /// Where a decrypted file is kept once fetched: in the cache folder, under its blob id, with its own
    /// name so that the system's viewers recognise it.
    func cachedURL(for file: VaultFile, in vault: SavedVault) -> URL {
        filesFolder.appending(path: vault.id, directoryHint: .isDirectory)
            .appending(path: String(file.blobId.suffix(32)), directoryHint: .isDirectory)
            .appending(path: VaultNaming.clean(VaultListing.name(of: file.path)))
    }

    func isCached(_ file: VaultFile, in vault: SavedVault) -> Bool {
        FileManager.default.fileExists(atPath: cachedURL(for: file, in: vault).path)
    }

    /// The decrypted file on disk, fetched and checked if it is not there yet.
    func localFile(for file: VaultFile, in vault: SavedVault) async throws -> URL {
        let target = cachedURL(for: file, in: vault)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let running = vault.id + "/" + file.blobId
        if let task = fetching[running] { return try await task.value }
        let handle = try await open(vault)
        let token = self.token
        let transport = self.transport(for: vault)
        let scratch = scratchFolder
        let blobId = file.blobId
        let task = Task { () throws -> URL in
            let partial = target.deletingLastPathComponent().appending(path: "partial-\(UUID().uuidString)")
            try await handle.download(file.path, to: partial, scratch: scratch, accessToken: token, transport: transport) { bytes in
                Task { @MainActor in self.fetchedBytes[blobId] = bytes }
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
            return target
        }
        fetching[running] = task
        defer {
            fetching[running] = nil
            fetchedBytes[blobId] = nil
        }
        return try await task.value
    }

    /// A file to drag out of the app, to the desktop or another app. It is fetched and decrypted when
    /// it is dropped, not when the drag begins.
    func itemProvider(for file: VaultFile, in vault: SavedVault) -> NSItemProvider {
        let name = VaultListing.name(of: file.path)
        let provider = NSItemProvider()
        provider.suggestedName = name
        let ext = name.split(separator: ".").last.map(String.init) ?? ""
        let type = UTType(filenameExtension: ext) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                do {
                    completion(try await self.localFile(for: file, in: vault), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    /// The largest image a thumbnail is made for without being asked: making one fetches the whole file.
    static let largestAutomaticThumbnail = 40_000_000

    func thumbnail(for file: VaultFile, in vault: SavedVault) async -> UIImage? {
        guard VaultListing.kind(of: file.path) == .image else { return nil }
        let kept = thumbnailFolder.appending(path: String(file.blobId.suffix(32)) + ".jpg")
        if let image = UIImage(contentsOfFile: kept.path) { return image }
        guard file.size <= Self.largestAutomaticThumbnail || isCached(file, in: vault) else { return nil }
        await thumbnails.acquire()
        let url = try? await localFile(for: file, in: vault)
        await thumbnails.release()
        guard let url else { return nil }
        let data = await Task.detached(priority: .utility) { Thumbnail.jpeg(of: url, maxPixel: 480) }.value
        guard let data else { return nil }
        try? FileManager.default.createDirectory(at: thumbnailFolder, withIntermediateDirectories: true)
        try? data.write(to: kept, options: .atomic)
        return UIImage(data: data)
    }

    // MARK: History

    /// What a commit changed, against its first parent.
    func changes(in commit: VaultCommit, of vault: SavedVault) async throws -> [VaultChange] {
        let handle = try await open(vault)
        let after = try await handle.files(in: commit)
        guard let parentId = commit.parents.first else { return VaultChange.between([], after) }
        let known = contents[vault.id]?.history.first { $0.commitId == parentId }
        var parent = known
        if parent == nil {
            parent = try await handle.history(limit: 500).first { $0.commitId == parentId }
        }
        guard let parent else { return VaultChange.between([], after) }
        return VaultChange.between(try await handle.files(in: parent), after)
    }

    func fingerprint(ofKey keyId: String, in vault: SavedVault) async -> String? {
        guard let handle = try? await open(vault) else { return nil }
        return try? await handle.signerFingerprint(keyId: keyId)
    }

    // MARK: Change one file

    /// What a write needs, or the reason there is none.
    func writing(to vault: SavedVault) async throws -> (handle: SGitVault, writeKey: SymmetricKey, token: String?) {
        let key = try await key(for: vault)
        guard let writeKey = key.writeKey else { throw VaultShelfError.readOnly }
        let token = self.token
        if !current(vault).onDevice, serverNeedsToken { throw VaultShelfError.noToken }
        return (try await open(vault), writeKey, token)
    }

    /// One commit that removes or renames, tried again when somebody else committed first.
    private func change(_ vault: SavedVault, staged: [VaultStagedFile], removing: [String], message: String) async throws {
        let (handle, writeKey, token) = try await writing(to: vault)
        let signer = try commitSigner()
        var attempt = 0
        while true {
            attempt += 1
            do {
                _ = try await handle.commit(staged: staged, removing: removing, message: message, signer: signer,
                                            writeKey: writeKey, accessToken: token, transport: transport(for: vault),
                                            alreadyUploaded: Set(staged.map(\.blobId)))
                break
            } catch VaultError.pushConflict where attempt < 3 {
                continue
            }
        }
        try await load(vault)
    }

    func delete(_ file: VaultFile, in vault: SavedVault) async throws {
        try await change(vault, staged: [], removing: [file.path],
                         message: VaultNaming.fit("Remove \(VaultListing.name(of: file.path))"))
    }

    /// Renames a file within its folder: the same object under a new name, so nothing is uploaded again.
    func rename(_ file: VaultFile, to newName: String, in vault: SavedVault) async throws {
        let name = VaultNaming.clean(newName)
        let folder = VaultListing.parent(of: file.path)
        let path = folder.isEmpty ? name : folder + "/" + name
        guard path != file.path else { return }
        if contents[vault.id]?.files.contains(where: { $0.path == path }) == true { throw VaultShelfError.nameTaken(name) }
        let same = VaultStagedFile(path: path, size: file.size, blobId: file.blobId, contentHash: file.contentHash ?? "",
                                   contentType: file.contentType ?? VaultBlobStager.contentType(for: path), large: file.large,
                                   ciphertextBytes: 0, ciphertext: scratchFolder)
        try await change(vault, staged: [same], removing: [file.path],
                         message: VaultNaming.fit("Rename \(VaultListing.name(of: file.path)) to \(name)"))
    }

    // MARK: The cache

    /// Bytes of decrypted files and thumbnails kept in the cache folder.
    func cacheBytes() -> Int {
        var total = 0
        for folder in [filesFolder, thumbnailFolder, scratchFolder, objectCache] {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in walker {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return total
    }

    func emptyCache() async {
        for folder in [filesFolder, thumbnailFolder, scratchFolder, objectCache] {
            try? FileManager.default.removeItem(at: folder)
        }
        for handle in opened.values { await handle.clearCache() }
    }

    static func describe(_ error: Error) -> String {
        if let vault = error as? VaultError { return vault.errorDescription ?? "\(vault)" }
        return error.localizedDescription
    }
}
