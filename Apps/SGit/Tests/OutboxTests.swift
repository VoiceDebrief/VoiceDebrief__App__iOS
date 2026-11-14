import CryptoKit
import Foundation
import SGitVault
import Testing
@testable import SGit

/// The whole path a selection takes, against a real vault held in a folder (the engine's own stand-in
/// for a server): nothing here pretends to be a server's answer.
@Suite("Adding files to a vault", .serialized)
@MainActor
struct OutboxTests {
    static func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sgit-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, count) }
        return data
    }

    static func shelf(_ transport: any VaultFileTransport) throws -> VaultShelf {
        VaultShelf(store: MemoryStore(), transport: transport, cacheRoot: try folder("cache"), localRoot: try folder("local"))
    }

    static func incoming(_ files: [(String, Data)]) throws -> [IncomingFile] {
        let dir = try folder("picked")
        return try files.map { name, data in
            let url = dir.appending(path: UUID().uuidString)
            try data.write(to: url)
            return IncomingFile(url: url, name: name)
        }
    }

    @Test func aSelectionBecomesOneSignedCommitAndIsReadBack() async throws {
        let transport = FolderVaultTransport(root: try Self.folder("server"))
        let shelf = try Self.shelf(transport)
        let vault = try #require(await shelf.create(name: "Team"))
        #expect(vault.onDevice)
        let outbox = Outbox(root: try Self.folder("outbox"))
        let clip = Self.random(5 * 1024 * 1024 + 9)
        let photo = Self.random(20_000)
        let job = try outbox.add(try Self.incoming([("photo.jpg", photo), ("clip.mov", clip), ("notes.txt", Data("hello\n".utf8))]),
                                 to: vault, folder: "trip", existing: [], shelf: shelf)
        #expect(job.message == "Add 3 files: photo.jpg, clip.mov, notes.txt")
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.isEmpty, "\(outbox.jobs.first?.problem ?? "")")
        #expect(!FileManager.default.fileExists(atPath: outbox.folder(of: job.id).path))

        let contents = try #require(shelf.contents[vault.id])
        #expect(contents.files.map(\.path) == ["trip/clip.mov", "trip/notes.txt", "trip/photo.jpg"])
        #expect(contents.head.message == job.message)
        #expect(contents.head.signature.isVerified)
        let clipFile = try #require(contents.files.first { $0.path == "trip/clip.mov" })
        #expect(clipFile.large)
        #expect(clipFile.contentType == "video/quicktime")

        // Read back through the cache, from disk to disk.
        let local = try await shelf.localFile(for: clipFile, in: vault)
        #expect(try Data(contentsOf: local) == clip)
        #expect(local.lastPathComponent == "clip.mov")
        #expect(shelf.isCached(clipFile, in: vault))

        // The browser's view of it.
        let top = VaultListing.of(contents.files, in: "")
        #expect(top.files.isEmpty)
        #expect(top.folders.map(\.name) == ["trip"])
        #expect(top.folders.first?.files == 3)
        #expect(VaultListing.of(contents.files, in: "trip").files.map(\.path) == ["trip/clip.mov", "trip/notes.txt", "trip/photo.jpg"])

        // History: what the commit changed, and that this device signed it.
        let changes = try await shelf.changes(in: contents.head, of: vault)
        #expect(changes.map(\.kind) == [.added, .added, .added])
        let keyId = try #require(contents.head.authorKeyId)
        let fingerprint = await shelf.fingerprint(ofKey: keyId, in: vault)
        #expect(fingerprint != nil)
        #expect(fingerprint == shelf.deviceFingerprint)

        // So far the vault is on this device only: the server holds nothing, and a teammate cannot add it.
        let teammate = try Self.shelf(transport)
        #expect(await teammate.add(keyText: vault.keyText, name: "Team") == nil)
        teammate.clearProblem()

        // Sent to the server, large file included. The device's own folder goes; the vault reads the same.
        #expect(await shelf.sendToServer(vault, pending: true) == false)
        shelf.clearProblem()
        #expect(await shelf.sendToServer(vault))
        #expect(shelf.current(vault).onDevice == false)
        #expect(!FileManager.default.fileExists(atPath: shelf.localRoot.appending(path: vault.id).path))
        let onServer = try await shelf.load(vault)
        #expect(onServer.head.commitId == contents.head.commitId)

        // The teammate opens it by its key and reads the large file byte for byte.
        let theirs = try #require(await teammate.add(keyText: vault.keyText, name: "Team"))
        let theirContents = try await teammate.load(theirs)
        let theirClip = try #require(theirContents.files.first { $0.path == "trip/clip.mov" })
        let theirLocal = try await teammate.localFile(for: theirClip, in: theirs)
        #expect(try Data(contentsOf: theirLocal) == clip)

        // Rename and delete are a commit each, and upload nothing.
        try await shelf.rename(clipFile, to: "film.mov", in: vault)
        let renamed = try #require(shelf.contents[vault.id])
        #expect(renamed.head.message == "Rename clip.mov to film.mov")
        let film = try #require(renamed.files.first { $0.path == "trip/film.mov" })
        #expect(film.blobId == clipFile.blobId)
        await #expect(throws: VaultShelfError.self) { try await shelf.rename(film, to: "notes.txt", in: vault) }
        try await shelf.delete(film, in: vault)
        let after = try #require(shelf.contents[vault.id])
        #expect(after.files.map(\.path) == ["trip/notes.txt", "trip/photo.jpg"])
        #expect(after.head.message == "Remove film.mov")
        #expect(after.history.count == 4)
    }

    @Test func aFailedUploadKeepsEverythingAndCarriesOnAfterARestart() async throws {
        let flaky = FlakyTransport(inner: FolderVaultTransport(root: try Self.folder("server")), failures: 1)
        let shelf = try Self.shelf(flaky)
        let vault = try #require(await shelf.create(name: "Team"))
        #expect(await shelf.sendToServer(vault))
        let root = try Self.folder("outbox")
        let outbox = Outbox(root: root)
        let big = Self.random(4 * 1024 * 1024 + 4_096)
        let job = try outbox.add(try Self.incoming([("big.bin", big), ("small.txt", Data("x".utf8))]),
                                 to: vault, folder: "", existing: [], shelf: shelf)
        await outbox.wait(for: job.id)

        // It failed, and says so; nothing reached the vault; the job is on disk with its ciphertext.
        let stopped = try #require(outbox.jobs.first)
        #expect(stopped.problem != nil)
        #expect(stopped.items.allSatisfy { $0.sealed != nil && $0.plainName == nil })
        let untouched = try await shelf.load(vault)
        #expect(untouched.files.isEmpty)

        // The app is closed and opened again: a new outbox finds the job and finishes it.
        let reopened = Outbox(root: root)
        #expect(reopened.jobs.map(\.id) == [job.id])
        reopened.resumeAll(shelf: shelf)
        await reopened.wait(for: job.id)
        #expect(reopened.jobs.isEmpty, "\(reopened.jobs.first?.problem ?? "")")
        let contents = try #require(shelf.contents[vault.id])
        #expect(contents.files.map(\.path) == ["big.bin", "small.txt"])
        let file = try #require(contents.files.first { $0.path == "big.bin" })
        let local = try await shelf.localFile(for: file, in: vault)
        #expect(try Data(contentsOf: local) == big)
        #expect(flaky.largeUploads == 2)
    }

    @Test func discardingRemovesTheJobAndItsFiles() async throws {
        let flaky = FlakyTransport(inner: FolderVaultTransport(root: try Self.folder("server")), failures: 100)
        let shelf = try Self.shelf(flaky)
        let vault = try #require(await shelf.create(name: "Team"))
        #expect(await shelf.sendToServer(vault))
        let outbox = Outbox(root: try Self.folder("outbox"))
        let job = try outbox.add(try Self.incoming([("big.bin", Self.random(4 * 1024 * 1024 + 1))]),
                                 to: vault, folder: "", existing: [], shelf: shelf)
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.count == 1)
        outbox.discard(job.id)
        #expect(outbox.jobs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outbox.folder(of: job.id).path))
    }

    @Test func aReadKeyCannotAdd() async throws {
        let transport = FolderVaultTransport(root: try Self.folder("server"))
        let owner = try Self.shelf(transport)
        let made = try #require(await owner.create(name: "Team"))
        #expect(await owner.sendToServer(made))
        let readKey = try await owner.key(for: made).exportReadKey()

        let reader = try Self.shelf(transport)
        let vault = try #require(await reader.add(keyText: readKey, name: "Theirs"))
        #expect(!vault.canWrite)
        let outbox = Outbox(root: try Self.folder("outbox"))
        let job = try outbox.add(try Self.incoming([("a.txt", Data("a".utf8))]), to: vault, folder: "", existing: [], shelf: reader)
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.first?.problem?.contains("read key") == true)
    }
}

@Suite("A vault on this device")
@MainActor
struct LocalVaultTests {
    @Test func creatingNeedsNoTokenAndNoServer() async throws {
        // The real server transport, and no token: nothing here may touch the network.
        let shelf = VaultShelf(store: MemoryStore(), cacheRoot: try OutboxTests.folder("cache"),
                               localRoot: try OutboxTests.folder("local"))
        #expect(!shelf.hasToken)
        let vault = try #require(await shelf.create(name: "Mine"))
        #expect(vault.onDevice)
        #expect(vault.canWrite)
        #expect(shelf.problem == nil)

        // It takes files at once.
        let outbox = Outbox(root: try OutboxTests.folder("outbox"))
        let job = try outbox.add(try OutboxTests.incoming([("a.txt", Data("a".utf8))]), to: vault, folder: "", existing: [], shelf: shelf)
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.isEmpty, "\(outbox.jobs.first?.problem ?? "")")
        let contents = try await shelf.load(vault)
        #expect(contents.files.map(\.path) == ["a.txt"])
        #expect(contents.head.signature.isVerified)

        // Sharing is the first thing that asks for a token, and says why. Nothing is sent without one.
        #expect(await shelf.sendToServer(vault) == false)
        #expect(shelf.problem?.contains("access key") == true)
        #expect(shelf.current(vault).onDevice)
    }

    @Test func aDroppedFolderKeepsItsShape() async throws {
        let shelf = try OutboxTests.shelf(FolderVaultTransport(root: try OutboxTests.folder("server")))
        let vault = try #require(await shelf.create(name: "Mine"))
        // A folder as it would be dragged in from the desktop.
        let dropped = try OutboxTests.folder("dropped").appending(path: "Summit", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dropped.appending(path: "day 1"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: dropped.appending(path: "day 1/a.txt"))
        try Data("two".utf8).write(to: dropped.appending(path: "b.txt"))
        let incoming = PickedFile.keepAll(scoped: dropped)
        #expect(incoming.count == 2)
        let outbox = Outbox(root: try OutboxTests.folder("outbox"))
        let job = try outbox.add(incoming, to: vault, folder: "photos", existing: [], shelf: shelf)
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.isEmpty, "\(outbox.jobs.first?.problem ?? "")")
        let contents = try await shelf.load(vault)
        #expect(contents.files.map(\.path) == ["photos/Summit/b.txt", "photos/Summit/day 1/a.txt"])
        #expect(FileManager.default.fileExists(atPath: dropped.appending(path: "b.txt").path), "the originals are left where they were")
    }

    @Test func whatWasSharedToTheAppBecomesAJob() async throws {
        let shelf = try OutboxTests.shelf(FolderVaultTransport(root: try OutboxTests.folder("server")))
        let inbox = try OutboxTests.folder("inbox")
        shelf.sharedInbox = inbox
        let vault = try #require(await shelf.create(name: "Mine"))
        // The app tells the extension which vaults there are: names and ids, and no key.
        let listed = SharedInbox.listed(in: inbox)
        #expect(listed.map(\.id) == [vault.id])
        let published = try String(contentsOf: SharedInbox.vaultList(in: inbox), encoding: .utf8)
        #expect(!published.contains(vault.keyText))

        // The extension keeps two files for that vault, and one for a vault this device does not know.
        let picked = try OutboxTests.incoming([("a.jpg", OutboxTests.random(9_000)), ("b.mov", OutboxTests.random(30_000))])
        try SharedInbox.keep(picked.map { (url: $0.url, name: $0.name) }, vaultId: vault.id, folder: "from phone", in: inbox)
        try SharedInbox.keep([(url: picked[0].url, name: "c.jpg")], vaultId: "gone1234", folder: "", in: inbox)
        #expect(SharedInbox.waiting(in: inbox).count == 2)

        let outbox = Outbox(root: try OutboxTests.folder("outbox"))
        #expect(outbox.takeShared(from: inbox, shelf: shelf) == 1)
        #expect(SharedInbox.waiting(in: inbox).isEmpty)
        let job = try #require(outbox.jobs.first)
        await outbox.wait(for: job.id)
        #expect(outbox.jobs.isEmpty, "\(outbox.jobs.first?.problem ?? "")")
        let contents = try await shelf.load(vault)
        #expect(contents.files.map(\.path) == ["from phone/a.jpg", "from phone/b.mov"])
        #expect(outbox.takeShared(from: nil, shelf: shelf) == 0)
    }

    @Test func aVaultSavedByTheFirstBuildIsOnTheServer() throws {
        let old = #"[{"id":"abcd1234","name":"Old","keyText":"some-pass:abcd1234","addedAt":0,"createdHere":true}]"#
        let vaults = try JSONDecoder().decode([SavedVault].self, from: Data(old.utf8))
        #expect(vaults.first?.onDevice == false)
        #expect(vaults.first?.canWrite == true)
    }

    @Test func forgettingAVaultOnThisDeviceDeletesIt() async throws {
        let shelf = try OutboxTests.shelf(FolderVaultTransport(root: try OutboxTests.folder("server")))
        let vault = try #require(await shelf.create(name: "Mine"))
        let folder = shelf.localRoot.appending(path: vault.id)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        shelf.remove(vault)
        #expect(shelf.vaults.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}

/// A folder that refuses its first large uploads, as a connection that drops would.
final class FlakyTransport: VaultTransport, VaultWriteTransport, VaultLargeTransport, @unchecked Sendable {
    struct Dropped: LocalizedError {
        var errorDescription: String? { "The connection was lost." }
    }

    let inner: FolderVaultTransport
    private let lock = NSLock()
    private var remaining: Int
    private var count = 0

    init(inner: FolderVaultTransport, failures: Int) {
        self.inner = inner
        self.remaining = failures
    }

    var label: String { inner.label }

    var largeUploads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    private func shouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if remaining > 0 {
            remaining -= 1
            return true
        }
        return false
    }

    func get(vaultId: String, path: String) async throws -> VaultResponse {
        try await inner.get(vaultId: vaultId, path: path)
    }

    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        try await inner.batch(vaultId: vaultId, writeKey: writeKey, accessToken: accessToken, operations: operations)
    }

    func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                     progress: @escaping @Sendable (Int) -> Void) async throws {
        if shouldFail() { throw Dropped() }
        try await inner.uploadLarge(vaultId: vaultId, fileId: fileId, from: file, writeKey: writeKey,
                                    accessToken: accessToken, progress: progress)
    }

    func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                       progress: @escaping @Sendable (Int) -> Void) async throws {
        try await inner.downloadLarge(vaultId: vaultId, fileId: fileId, to: file, expectedBytes: expectedBytes,
                                      accessToken: accessToken, progress: progress)
    }
}
