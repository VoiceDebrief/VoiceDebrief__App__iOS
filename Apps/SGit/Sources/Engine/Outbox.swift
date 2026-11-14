import Foundation
import Observation
import SGitVault

/// One file on its way into a vault.
struct UploadItem: Codable, Identifiable, Hashable, Sendable {
    /// What staging produced: enough to name the file in a commit without the plain copy.
    struct Sealed: Codable, Hashable, Sendable {
        var blobId: String
        var contentHash: String
        var contentType: String
        var large: Bool
        var ciphertextBytes: Int
    }

    var id: UUID
    /// The name shown, and the last part of `path`.
    var name: String
    /// Where the file goes in the vault.
    var path: String
    var bytes: Int
    /// The plain copy inside the job's folder, until it has been encrypted.
    var plainName: String?
    var sealed: Sealed?
    /// The server holds the encrypted object.
    var uploaded = false
}

/// One selection: the files picked together, which become one commit.
struct UploadJob: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var vaultId: String
    var vaultName: String
    var folder: String
    var createdAt: Date
    var message: String
    var items: [UploadItem]
    /// Why it stopped, when it has.
    var problem: String?

    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }
}

/// What one item is doing now. Not kept: it is rebuilt as the work runs.
struct ItemProgress: Equatable, Sendable {
    enum Phase: String, Sendable { case waiting, encrypting, uploading, uploaded }
    var phase: Phase = .waiting
    /// 0 to 1 within the phase.
    var fraction: Double = 0
}

/// A file picked by the user, already copied somewhere the app owns.
struct IncomingFile: Sendable {
    let url: URL
    let name: String
}

/// Files on their way into vaults. A selection is copied into the app's own storage before anything
/// else happens, and every step after that is recorded on disk, so that closing the app, losing the
/// connection or a refused push loses nothing: the job is still here and can be taken up again.
///
///     picked files → copied into the job → encrypted to disk under their object ids
///                  → uploaded (large ones in parts) → one signed commit → the job is removed
@MainActor
@Observable
final class Outbox {
    let root: URL
    private(set) var jobs: [UploadJob] = []
    private(set) var progress: [UUID: ItemProgress] = [:]
    private(set) var running: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "outbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        load()
    }

    // MARK: On disk

    func folder(of job: UUID) -> URL { root.appending(path: job.uuidString, directoryHint: .isDirectory) }
    private func plainFolder(_ job: UUID) -> URL { folder(of: job).appending(path: "plain", directoryHint: .isDirectory) }
    private func sealedFolder(_ job: UUID) -> URL { folder(of: job).appending(path: "sealed", directoryHint: .isDirectory) }
    private func record(_ job: UUID) -> URL { folder(of: job).appending(path: "job.json") }

    private func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [UploadJob] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: "job.json")),
                  let job = try? JSONDecoder().decode(UploadJob.self, from: data) else { continue }
            found.append(job)
        }
        jobs = found.sorted { $0.createdAt < $1.createdAt }
    }

    private func save(_ job: UploadJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job } else { jobs.append(job) }
        guard let data = try? JSONEncoder().encode(job) else { return }
        try? data.write(to: record(job.id), options: .atomic)
    }

    private func update(_ id: UUID, _ change: (inout UploadJob) -> Void) {
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        change(&job)
        save(job)
    }

    func jobs(for vault: SavedVault) -> [UploadJob] { jobs.filter { $0.vaultId == vault.id } }

    /// How far a job is, 0 to 1, by bytes: encrypting is the first tenth of each file, uploading the rest.
    func fraction(of job: UploadJob) -> Double {
        let total = max(job.totalBytes, 1)
        var done = 0.0
        for item in job.items {
            let state = progress[item.id] ?? ItemProgress(phase: item.uploaded ? .uploaded : .waiting)
            let part: Double
            switch state.phase {
            case .waiting: part = item.sealed == nil ? 0 : 0.1
            case .encrypting: part = 0.1 * state.fraction
            case .uploading: part = 0.1 + 0.9 * state.fraction
            case .uploaded: part = 1
            }
            done += part * Double(item.bytes)
        }
        return min(1, done / Double(total))
    }

    // MARK: Taking files in

    /// Copies the picked files into a new job and starts it. Once this returns the selection is safe.
    /// - Parameter existing: the paths already in the vault, so that names do not collide.
    @discardableResult
    func add(_ files: [IncomingFile], to vault: SavedVault, folder: String, existing: [String],
             shelf: VaultShelf, moving: Bool = true) throws -> UploadJob {
        let id = UUID()
        try FileManager.default.createDirectory(at: plainFolder(id), withIntermediateDirectories: true)
        let paths = VaultNaming.paths(for: files.map(\.name), in: folder, existing: existing)
        var items: [UploadItem] = []
        for (index, file) in files.enumerated() {
            let itemId = UUID()
            let plainName = "\(index)-\(itemId.uuidString)"
            let target = plainFolder(id).appending(path: plainName)
            if moving {
                try FileManager.default.moveItem(at: file.url, to: target)
            } else {
                try FileManager.default.copyItem(at: file.url, to: target)
            }
            let bytes = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            items.append(UploadItem(id: itemId, name: VaultListing.name(of: paths[index]), path: paths[index],
                                    bytes: bytes, plainName: plainName))
        }
        let job = UploadJob(id: id, vaultId: vault.id, vaultName: vault.name, folder: folder, createdAt: Date(),
                            message: VaultNaming.addMessage(items.map(\.name)), items: items)
        save(job)
        start(id, shelf: shelf)
        return job
    }

    // MARK: Running

    /// Starts every job that is not running: called when the app opens.
    func resumeAll(shelf: VaultShelf) {
        for job in jobs where !running.contains(job.id) { start(job.id, shelf: shelf) }
    }

    func start(_ id: UUID, shelf: VaultShelf) {
        guard !running.contains(id), jobs.contains(where: { $0.id == id }) else { return }
        running.insert(id)
        update(id) { $0.problem = nil }
        tasks[id] = Task { [weak self] in
            await self?.run(id, shelf: shelf)
            self?.running.remove(id)
            self?.tasks[id] = nil
        }
    }

    /// Waits for a job that is running (tests).
    func wait(for id: UUID) async {
        await tasks[id]?.value
    }

    /// Stops a job and removes everything it holds. Objects already uploaded stay on the server unnamed;
    /// no commit refers to them.
    func discard(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        running.remove(id)
        if let job = jobs.first(where: { $0.id == id }) {
            for item in job.items { progress[item.id] = nil }
        }
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(of: id))
    }

    private func setProgress(_ item: UUID, _ phase: ItemProgress.Phase, _ fraction: Double) {
        progress[item] = ItemProgress(phase: phase, fraction: min(1, max(0, fraction)))
    }

    private func run(_ id: UUID, shelf: VaultShelf) async {
        do {
            try await work(id, shelf: shelf)
        } catch is CancellationError {
            // Discarded, or the app is closing: the record on disk says where to carry on.
        } catch {
            update(id) { $0.problem = VaultShelf.describe(error) }
        }
    }

    private func work(_ id: UUID, shelf: VaultShelf) async throws {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard let vault = shelf.vaults.first(where: { $0.id == job.vaultId }) else {
            throw VaultError.vaultNotFoundOrWrongKey(vaultId: job.vaultId)
        }
        let (handle, writeKey, token) = try await shelf.writing(to: vault)
        let signer = try shelf.commitSigner()
        let stager = try await handle.stager()
        let sealedDir = sealedFolder(id)

        // 1. Encrypt each file to disk. The plain copy goes once its ciphertext is recorded.
        for item in job.items where item.sealed == nil {
            try Task.checkCancellation()
            guard let plainName = item.plainName else { continue }
            let plain = plainFolder(id).appending(path: plainName)
            let itemId = item.id
            let total = max(item.bytes, 1)
            setProgress(itemId, .encrypting, 0)
            let staged = try await stager.stage(file: plain, as: item.path, in: sealedDir) { done in
                Task { @MainActor in self.setProgress(itemId, .encrypting, Double(done) / Double(total)) }
            }
            update(id) { job in
                guard let index = job.items.firstIndex(where: { $0.id == itemId }) else { return }
                job.items[index].sealed = UploadItem.Sealed(blobId: staged.blobId, contentHash: staged.contentHash,
                                                           contentType: staged.contentType, large: staged.large,
                                                           ciphertextBytes: staged.ciphertextBytes)
                job.items[index].bytes = staged.size
                job.items[index].plainName = nil
            }
            try? FileManager.default.removeItem(at: plain)
            setProgress(itemId, .waiting, 0)
        }

        // 2. Upload what the server lacks and commit. A refused push is tried again on the new head.
        guard let ready = jobs.first(where: { $0.id == id }) else { return }
        var staged: [VaultStagedFile] = []
        var byBlob: [String: (item: UUID, bytes: Int)] = [:]
        for item in ready.items {
            guard let sealed = item.sealed else { continue }
            staged.append(VaultStagedFile(path: item.path, size: item.bytes, blobId: sealed.blobId,
                                          contentHash: sealed.contentHash, contentType: sealed.contentType,
                                          large: sealed.large, ciphertextBytes: sealed.ciphertextBytes,
                                          ciphertext: sealedDir.appending(path: sealed.blobId)))
            byBlob[sealed.blobId] = (item.id, max(sealed.ciphertextBytes, 1))
            if item.uploaded { setProgress(item.id, .uploaded, 1) }
        }
        let lookup = byBlob
        var attempt = 0
        while true {
            attempt += 1
            let already = Set((jobs.first { $0.id == id }?.items ?? []).filter(\.uploaded).compactMap { $0.sealed?.blobId })
            do {
                _ = try await handle.commit(
                    staged: staged, message: ready.message, signer: signer, writeKey: writeKey, accessToken: token,
                    transport: shelf.transport(for: vault), alreadyUploaded: already,
                    uploaded: { blobId in
                        Task { @MainActor in
                            guard let entry = lookup[blobId] else { return }
                            self.update(id) { job in
                                if let index = job.items.firstIndex(where: { $0.id == entry.item }) { job.items[index].uploaded = true }
                            }
                            self.setProgress(entry.item, .uploaded, 1)
                        }
                    },
                    progress: { blobId, sent in
                        Task { @MainActor in
                            guard let entry = lookup[blobId], self.progress[entry.item]?.phase != .uploaded else { return }
                            self.setProgress(entry.item, .uploading, Double(sent) / Double(entry.bytes))
                        }
                    })
                break
            } catch VaultError.pushConflict where attempt < 4 {
                continue
            }
        }

        // 3. Committed and read back: the job is done.
        for item in ready.items { progress[item.id] = nil }
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(of: id))
        _ = try? await shelf.load(vault)
    }
}
