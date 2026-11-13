import Foundation
import Testing
import SGitVault
@testable import VoiceDebrief

/// A server that cannot be reached: every request fails, as with no network.
struct NoNetwork: VaultTransport, VaultWriteTransport {
    var label: String { "no network" }
    func get(vaultId: String, path: String) async throws -> VaultResponse { throw URLError(.notConnectedToInternet) }
    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult { throw URLError(.notConnectedToInternet) }
}

/// One device in a test: its own Keychain (in memory), its own folders, and a folder standing in for
/// every server (laid out as a server holds vaults: `<vault id>/bare/…`).
@MainActor
struct Device {
    let store: MemoryStore
    let root: URL
    let book: VaultBook

    static func folder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// - Parameter server: the folder that plays the server, or nil for no network at all.
    init(server: URL?, store seeded: MemoryStore? = nil) {
        root = Self.folder("device")
        store = seeded ?? MemoryStore()
        book = VaultBook(store: store, localRoot: root.appending(path: "vaults"), cacheRoot: root.appending(path: "cache"),
                         connect: { _ in
                             if let server { return FolderVaultTransport(root: server, perVaultSubfolder: "") }
                             return NoNetwork()
                         })
    }
}

@Suite("Vault book")
@MainActor
struct VaultBookTests {
    static func run(_ words: String = "Hello there.") -> DebriefRun {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 900, text: words)])
        run.debrief = "## Key points\n- Hello.\n"
        return run
    }

    // MARK: The files a debrief becomes

    @Test func aDebriefBecomesOneDatedFolder() throws {
        let date = Date(timeIntervalSince1970: 1_794_528_000)       // 13 November 2026, 00:00 UTC
        let files = VaultBook.files(for: Self.run(), audio: Data([1, 2, 3]), audioName: "voice-note-1.m4a", id: "abc12345", date: date)
        #expect(Set(files.keys) == [
            "debriefs/2026/11/13/abc12345/debrief.md",
            "debriefs/2026/11/13/abc12345/transcript.md",
            "debriefs/2026/11/13/abc12345/run.json",
            "debriefs/2026/11/13/abc12345/audio.m4a",
        ])
        #expect(files["debriefs/2026/11/13/abc12345/transcript.md"] == Data("[00:00] Hello there.\n".utf8))
        #expect(files["debriefs/2026/11/13/abc12345/audio.m4a"] == Data([1, 2, 3]))
        let saved = try JSONDecoder().decode(DebriefRun.self, from: try #require(files["debriefs/2026/11/13/abc12345/run.json"]))
        #expect(saved == Self.run())
    }

    @Test func withoutAudioOrDebriefOnlyWhatExistsIsWritten() {
        var run = Self.run()
        run.debrief = nil
        let files = VaultBook.files(for: run, audio: nil, audioName: nil, id: "x", date: Date(timeIntervalSince1970: 0))
        #expect(Set(files.keys) == ["debriefs/1970/01/01/x/transcript.md", "debriefs/1970/01/01/x/run.json"])
    }

    @Test func theSigningKeyIsMadeOnceAndKept() throws {
        let store = MemoryStore()
        let first = try VaultBook(store: store, localRoot: Device.folder("a"), cacheRoot: Device.folder("b")).commitSigner()
        let second = try VaultBook(store: store, localRoot: Device.folder("a"), cacheRoot: Device.folder("b")).commitSigner()
        #expect(first.keyId == second.keyId)
        #expect(first.publicKeyPEM == second.publicKeyPEM)
        #expect(first.keyId.hasPrefix("key-rnd-imm-"))
        let other = try VaultBook(store: MemoryStore(), localRoot: Device.folder("a"), cacheRoot: Device.folder("b")).commitSigner()
        #expect(other.keyId != first.keyId)
    }

    @Test func aVaultKeyWritesAndAReadKeyDoesNot() {
        let vaultKey = SavedVault(id: "abcd1234", name: "a", keyText: VaultCreate.newKeyText(), addedAt: Date(), createdHere: true)
        #expect(vaultKey.canWrite)
        let readKey = SavedVault(id: "abcd1234", name: "b", keyText: "sgit_private_read_" + String(repeating: "0", count: 64) + ":abcd1234",
                                 addedAt: Date(), createdHere: false)
        #expect(!readKey.canWrite)
    }

    // MARK: Local first

    @Test func aVaultIsCreatedAndANoteSavedWithNoTokenAndNoNetwork() async throws {
        let device = Device(server: nil)
        let book = device.book
        #expect(book.remotes.isEmpty)
        await book.create(name: "Notes")
        #expect(book.problem == nil)
        let vault = try #require(book.vaults.first)
        #expect(vault.onDevice)
        #expect(vault.remoteId == nil)
        #expect(vault.canWrite)
        #expect(book.status(of: vault) == "On this device only")
        // It is in the folder for vaults on this device, in the server's layout.
        let bare = book.folder(of: vault.id).appending(path: "bare")
        #expect(FileManager.default.fileExists(atPath: bare.appending(path: "indexes").path))
        #expect(device.root.appending(path: "vaults").path == book.localRoot.path)

        let empty = try await book.contents(of: vault)
        #expect(empty.head.message == "Vault created")
        #expect(empty.head.signature.isVerified)
        #expect(empty.files.isEmpty)
        #expect(empty.head.commitId == vault.localHead)

        let said = try await book.save(run: Self.run(), audioURL: nil, to: vault)
        #expect(said.contains("on this device"))
        let after = try await book.contents(of: vault)
        #expect(after.files.count == 3)
        #expect(after.history.count == 2)
        #expect(after.history.allSatisfy { $0.signature.isVerified })
        let transcript = try #require(after.files.first { $0.path.hasSuffix("transcript.md") })
        #expect(try await book.data(of: transcript.path, in: vault) == Data("[00:00] Hello there.\n".utf8))
        #expect(book.current(vault).localHead == after.head.commitId)

        // A second launch (a new book over the same Keychain and folders) still opens it, still offline.
        let again = VaultBook(store: device.store, localRoot: book.localRoot, cacheRoot: book.cacheRoot, connect: { _ in NoNetwork() })
        let reopened = try await again.contents(of: try #require(again.vaults.first))
        #expect(reopened.files.count == 3)
    }

    @Test func forgettingAVaultDeletesThisDevicesCopy() async throws {
        let book = Device(server: nil).book
        await book.create(name: "")
        let vault = try #require(book.vaults.first)
        #expect(vault.name == "Vault \(vault.id)")
        #expect(FileManager.default.fileExists(atPath: book.folder(of: vault.id).path))
        book.remove(vault)
        #expect(book.vaults.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: book.folder(of: vault.id).path))
    }

    // MARK: Servers

    @Test func aServerHasANameAnAddressAndATokenInTheKeychain() throws {
        let device = Device(server: nil)
        let book = device.book
        #expect(book.addRemote(name: "", address: "not an address") == nil)
        #expect(book.problem != nil)
        #expect(book.addRemote(name: "", address: "http://plain.example") == nil)
        #expect(book.remotes.isEmpty)

        let remote = try #require(book.addRemote(name: " Mine ", address: VaultRemote.suggestedAddress, token: "  abc  "))
        #expect(book.problem == nil)
        #expect(remote.name == "Mine")
        #expect(remote.url.host() == "dev.send.sgraph.ai")
        #expect(book.hasToken(remote))
        #expect(device.store.get(VaultBook.tokenName(remote.id)) == Data("abc".utf8))
        // The token is not in the list of servers.
        #expect(!String(decoding: try #require(device.store.get("remotes")), as: UTF8.self).contains("abc"))

        let reopened = VaultBook(store: device.store, localRoot: book.localRoot, cacheRoot: book.cacheRoot)
        #expect(reopened.remotes == [remote])
        #expect(reopened.hasToken(remote))

        book.setToken("", for: remote)
        #expect(!book.hasToken(remote))
        #expect(device.store.get(VaultBook.tokenName(remote.id)) == nil)

        let unnamed = try #require(book.addRemote(name: "", address: "https://vaults.example/"))
        #expect(unnamed.name == "vaults.example")
        #expect(!book.hasToken(unnamed))
    }

    // MARK: Push and pull

    @Test func aLocalVaultIsPushedThenAheadThenPushedAgain() async throws {
        let server = Device.folder("server")
        let device = Device(server: server)
        let book = device.book
        await book.create(name: "Notes")
        let vault = try #require(book.vaults.first)
        _ = try await book.save(run: Self.run(), audioURL: nil, to: vault)

        // No server chosen: push says so and sends nothing.
        await book.push(vault)
        #expect(book.problem?.contains("no server") == true)

        // A server without a token: the push fails and the vault says why.
        let remote = try #require(book.addRemote(name: "Test server", address: "https://server.example"))
        book.setRemote(remote.id, for: vault)
        #expect(book.status(of: vault) == "On this device; not yet pushed to Test server")
        await book.push(vault)
        #expect(book.status(of: vault).hasPrefix("Push to Test server failed: no access token"))
        #expect(!FileManager.default.fileExists(atPath: server.appending(path: vault.id).path))

        // With a token it goes.
        book.setToken("token", for: remote)
        await book.push(vault)
        #expect(book.problem == nil)
        #expect(book.current(vault).pushProblem == nil)
        #expect(book.status(of: vault).hasPrefix("On this device and on Test server"))
        #expect(book.notice?.hasPrefix("Pushed 2 commits") == true)
        #expect(FileManager.default.fileExists(atPath: server.appending(path: "\(vault.id)/bare/indexes").path))
        await book.push(vault)
        #expect(book.notice == "Test server already had everything.")

        // Another device opens it from the server with the key alone.
        let other = Device(server: server)
        let theirs = try #require(other.book.addRemote(name: "Test server", address: "https://server.example"))
        await other.book.add(keyText: vault.keyText, name: "Theirs", from: theirs)
        #expect(other.book.problem == nil)
        let added = try #require(other.book.vaults.first)
        #expect(!added.onDevice)
        #expect(other.book.status(of: added) == "On Test server only, not kept on this device")
        #expect(try await other.book.contents(of: added).files.count == 3)

        // A second note: ahead of the server until pushed.
        let said = try await book.save(run: Self.run("Second."), audioURL: nil, to: vault)
        #expect(said.contains("Not yet on Test server"))
        #expect(book.status(of: vault) == "Ahead of Test server: changes here have not been pushed")
        #expect(try await other.book.contents(of: added).files.count == 3)
        await book.push(vault)
        #expect(book.notice?.hasPrefix("Pushed 1 commit ") == true)
        #expect(book.status(of: vault).hasPrefix("On this device and on Test server"))
        #expect(try await other.book.contents(of: added).files.count == 6)
    }

    @Test func aVaultOnAServerIsCopiedToThisDeviceAndPulled() async throws {
        let server = Device.folder("server")
        let first = Device(server: server).book
        await first.create(name: "Notes")
        let vault = try #require(first.vaults.first)
        let remote = try #require(first.addRemote(name: "S", address: "https://server.example", token: "t"))
        first.setRemote(remote.id, for: vault)
        _ = try await first.save(run: Self.run(), audioURL: nil, to: vault)
        await first.push(vault)

        let second = Device(server: server).book
        let theirs = try #require(second.addRemote(name: "S", address: "https://server.example"))
        await second.add(keyText: vault.keyText, name: "", from: theirs)
        let copy = try #require(second.vaults.first)
        await second.pull(copy)
        #expect(second.problem == nil)
        #expect(second.current(copy).onDevice)
        #expect(second.notice?.hasPrefix("Fetched 2 commits") == true)
        #expect(FileManager.default.fileExists(atPath: second.folder(of: copy.id).appending(path: "bare/data").path))
        #expect(try await second.contents(of: copy).files.count == 3)

        // The first device moves on and pushes; the second pulls it forward.
        _ = try await first.save(run: Self.run("More."), audioURL: nil, to: vault)
        await first.push(vault)
        #expect(try await second.contents(of: copy).files.count == 3)
        await second.pull(copy)
        #expect(second.notice?.hasPrefix("Fetched 1 commit ") == true)
        let pulled = try await second.contents(of: copy)
        #expect(pulled.files.count == 6)
        #expect(pulled.history.allSatisfy { $0.signature.isVerified })
        await second.pull(copy)
        #expect(second.notice == "This device already had everything on S.")
    }

    @Test func whenBothSidesChangedNothingIsOverwrittenAndItSaysAMergeIsNeeded() async throws {
        let server = Device.folder("server")
        let first = Device(server: server).book
        await first.create(name: "Notes")
        let vault = try #require(first.vaults.first)
        let remote = try #require(first.addRemote(name: "S", address: "https://server.example", token: "t"))
        first.setRemote(remote.id, for: vault)
        await first.push(vault)

        let second = Device(server: server).book
        let theirs = try #require(second.addRemote(name: "S", address: "https://server.example", token: "t"))
        await second.add(keyText: vault.keyText, name: "", from: theirs)
        let copy = try #require(second.vaults.first)
        await second.pull(copy)

        // Both write. The first to push wins; the second is told, and the server keeps the first's head.
        _ = try await first.save(run: Self.run("From the first."), audioURL: nil, to: vault)
        _ = try await second.save(run: Self.run("From the second."), audioURL: nil, to: copy)
        await first.push(vault)
        let pushed = try #require(first.current(vault).remoteHead)

        await second.push(copy)
        #expect(second.status(of: copy).contains("merge"))
        #expect(second.status(of: copy).hasPrefix("Push to S failed"))
        await second.pull(copy)
        #expect(second.problem?.contains("merge") == true)
        // The second device still has its own note, and the server still has the first's.
        #expect(try await second.contents(of: copy).files.count == 3)
        let reader = Device(server: server).book
        let readers = try #require(reader.addRemote(name: "S", address: "https://server.example"))
        await reader.add(keyText: vault.keyText, name: "", from: readers)
        #expect(reader.vaults.first?.remoteHead == pushed)

        // A device that is merely behind is told to pull, and pulling then lets it push.
        let third = Device(server: server).book
        let thirds = try #require(third.addRemote(name: "S", address: "https://server.example", token: "t"))
        await third.add(keyText: vault.keyText, name: "", from: thirds)
        let late = try #require(third.vaults.first)
        await third.pull(late)
        _ = try await first.save(run: Self.run("Again."), audioURL: nil, to: vault)
        await first.push(vault)
        await third.push(late)
        #expect(third.status(of: late).contains("Pull first"))
        await third.pull(late)
        await third.push(late)
        #expect(third.status(of: late).hasPrefix("On this device and on S"))
    }

    @Test func aServerHoldingAVaultsOnlyCopyCannotBeRemoved() async throws {
        let server = Device.folder("server")
        let first = Device(server: server).book
        await first.create(name: "Notes")
        let vault = try #require(first.vaults.first)
        let remote = try #require(first.addRemote(name: "S", address: "https://server.example", token: "t"))
        first.setRemote(remote.id, for: vault)
        await first.push(vault)

        let second = Device(server: server)
        let theirs = try #require(second.book.addRemote(name: "S", address: "https://server.example", token: "t"))
        await second.book.add(keyText: vault.keyText, name: "", from: theirs)
        let copy = try #require(second.book.vaults.first)
        second.book.removeRemote(theirs)
        #expect(second.book.remotes.count == 1)
        #expect(second.book.problem?.contains("kept only on S") == true)
        await second.book.pull(copy)
        second.book.removeRemote(theirs)
        #expect(second.book.remotes.isEmpty)
        #expect(second.store.get(VaultBook.tokenName(theirs.id)) == nil)
        #expect(second.book.status(of: copy) == "On this device only")
        #expect(try await second.book.contents(of: copy).head.signature.isVerified)
    }

    // MARK: Vaults from earlier builds

    @Test func aVaultFromAnEarlierVersionKeepsWorkingOnItsServer() async throws {
        // What an earlier build left: a vault that exists only on the server, its key and one token in the Keychain.
        let server = Device.folder("server")
        let signer = SoftwareCommitSigner()
        let created = try await VaultCreate.create(signer: signer, accessToken: nil,
                                                   writer: FolderVaultTransport(root: server, perVaultSubfolder: ""))
        let store = MemoryStore()
        let earlier: [[String: Any]] = [["id": created.key.vaultId, "name": "Old", "keyText": created.keyText,
                                         "addedAt": 800_000_000.0, "createdHere": true]]
        store.set("vaults", try JSONSerialization.data(withJSONObject: earlier))
        store.set("access-token", Data("old-token".utf8))

        let device = Device(server: server, store: store)
        let book = device.book
        let remote = try #require(book.remotes.first)
        #expect(book.remotes.count == 1)
        #expect(remote.url == VaultAddress.defaultServer)
        #expect(book.hasToken(remote))
        #expect(store.get(VaultBook.tokenName(remote.id)) == Data("old-token".utf8))
        #expect(store.get("access-token") == nil)
        let vault = try #require(book.vaults.first)
        #expect(!vault.onDevice)
        #expect(vault.remoteId == remote.id)
        #expect(book.status(of: vault) == "On dev.send.sgraph.ai only, not kept on this device")

        // It opens, and a note is saved straight to the server, as before.
        #expect(try await book.contents(of: vault).head.commitId == created.commitId)
        let said = try await book.save(run: Self.run(), audioURL: nil, to: vault)
        #expect(said.contains("on dev.send.sgraph.ai"))
        #expect(try await book.contents(of: vault).files.count == 3)
        #expect(!FileManager.default.fileExists(atPath: book.folder(of: vault.id).path))

        // A second launch changes nothing more.
        let again = Device(server: server, store: store).book
        #expect(again.remotes == [remote])
        #expect(again.vaults.first?.remoteId == remote.id)

        // And it can be brought onto the device.
        await book.pull(vault)
        #expect(book.current(vault).onDevice)
        #expect(try await book.contents(of: vault).files.count == 3)
        #expect(book.status(of: vault).hasPrefix("On this device and on dev.send.sgraph.ai"))
    }

    @Test func withoutItsTokenAVaultOnAServerSaysWhatSavingNeeds() async throws {
        let server = Device.folder("server")
        let created = try await VaultCreate.create(signer: SoftwareCommitSigner(), accessToken: nil,
                                                   writer: FolderVaultTransport(root: server, perVaultSubfolder: ""))
        let store = MemoryStore()
        let earlier: [[String: Any]] = [["id": created.key.vaultId, "name": "Old", "keyText": created.keyText,
                                         "addedAt": 800_000_000.0, "createdHere": true]]
        store.set("vaults", try JSONSerialization.data(withJSONObject: earlier))
        let book = Device(server: server, store: store).book
        let vault = try #require(book.vaults.first)
        #expect(book.remotes.count == 1)
        await #expect(throws: VaultBookError.noToken(server: "dev.send.sgraph.ai")) {
            _ = try await book.save(run: Self.run(), audioURL: nil, to: vault)
        }
    }

    // MARK: What the screens say

    @Test func theStatusLineSaysWhereAVaultIs() {
        var vault = SavedVault(id: "abcd1234", name: "a", keyText: "k", addedAt: Date(), createdHere: true)
        #expect(VaultBook.status(of: vault, server: "S") == "On S only, not kept on this device")
        vault.onDevice = true
        #expect(VaultBook.status(of: vault, server: nil) == "On this device only")
        vault.remoteId = "r"
        vault.localHead = "one"
        #expect(VaultBook.status(of: vault, server: "S") == "On this device; not yet pushed to S")
        vault.remoteHead = "one"
        #expect(VaultBook.status(of: vault, server: "S") == "On this device and on S")
        vault.localHead = "two"
        #expect(VaultBook.status(of: vault, server: "S") == "Ahead of S: changes here have not been pushed")
        vault.pushProblem = "HTTP 401 for batch"
        #expect(VaultBook.status(of: vault, server: "S") == "Push to S failed: HTTP 401 for batch")
    }

    @Test func forgettingSaysWhatWouldBeLost() {
        var vault = SavedVault(id: "abcd1234", name: "a", keyText: "k", addedAt: Date(), createdHere: true)
        #expect(VaultDetailView.forgetWarning(vault, server: "S").hasPrefix("The vault stays on S"))
        vault.onDevice = true
        #expect(VaultDetailView.forgetWarning(vault, server: nil).contains("only on this device"))
        vault.remoteId = "r"
        vault.localHead = "two"
        vault.remoteHead = "one"
        #expect(VaultDetailView.forgetWarning(vault, server: "S").contains("has not been pushed to S"))
        vault.remoteHead = "two"
        #expect(VaultDetailView.forgetWarning(vault, server: "S").contains("stays on S"))
    }
}
