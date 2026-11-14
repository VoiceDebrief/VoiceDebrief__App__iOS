import CryptoKit
import Foundation
import Security
import XCTest
@testable import SGitVault

/// Files over 4 MB (issue 023): the streaming cipher against CryptoKit, staging to disk, a commit of
/// staged files, reading them back, and both directions against sgit itself:
/// - what Swift writes here is exported (SGITVAULT_ROUNDTRIP_OUT) for sgit to clone on Linux;
/// - what sgit wrote on Linux (SGITVAULT_SGIT_WROTE) is read here.
@MainActor
final class LargeFileTests: XCTestCase {

    func randomData(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        XCTAssertEqual(status, errSecSuccess)
        return data
    }

    func temporaryFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sgitvault-\(name)-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: The cipher

    func testStreamSealsWhatCryptoKitOpens() throws {
        let key = SymmetricKey(size: .bits256)
        for count in [0, 1, 15, 16, 17, 31, 32, 33, 255, 4_096, 65_537, 300_001] {
            let plain = randomData(max(count, 1)).prefix(count)
            let iv = Data(AES.GCM.Nonce())
            let stream = try VaultGCMStream(key: key, iv: iv, direction: .seal)
            var sealed = iv
            // Pieces of awkward lengths, so blocks straddle them.
            var offset = 0
            var step = 1
            while offset < plain.count {
                let end = min(offset + step, plain.count)
                sealed += try stream.update(Data(plain[plain.startIndex + offset..<plain.startIndex + end]))
                offset = end
                step = step * 3 + 7
            }
            sealed += stream.finish()
            let opened = try AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: key)
            XCTAssertEqual(opened, Data(plain), "length \(count)")
            // And byte for byte what CryptoKit seals with the same iv.
            let reference = try VaultCrypto.seal(Data(plain), key: key, iv: iv)
            XCTAssertEqual(sealed, reference, "length \(count)")
        }
    }

    func testStreamOpensWhatCryptoKitSeals() throws {
        let key = SymmetricKey(size: .bits256)
        for count in [0, 1, 16, 17, 1_000, 70_001] {
            let plain = randomData(max(count, 1)).prefix(count)
            let sealed = try VaultCrypto.seal(Data(plain), key: key)
            let iv = sealed.prefix(12)
            let body = sealed.dropFirst(12).dropLast(16)
            let stream = try VaultGCMStream(key: key, iv: Data(iv), direction: .open)
            var opened = Data()
            var rest = Data(body)
            while !rest.isEmpty {
                let piece = rest.prefix(1_000)
                opened += try stream.update(Data(piece))
                rest = Data(rest.dropFirst(piece.count))
            }
            XCTAssertEqual(opened, Data(plain), "length \(count)")
            XCTAssertEqual(stream.finish(), Data(sealed.suffix(16)), "tag, length \(count)")
        }
    }

    func testAFileIsSealedAndOpenedAndATamperedOneIsRefused() throws {
        let folder = try temporaryFolder("cipher")
        let key = SymmetricKey(size: .bits256)
        let plain = randomData(3 * 1024 * 1024 + 11)
        let source = folder.appending(path: "plain.bin")
        try plain.write(to: source)
        let sealedURL = folder.appending(path: "sealed.bin")
        let sealed = try VaultFileCipher.seal(file: source, to: sealedURL, key: key)
        XCTAssertEqual(sealed.plaintextBytes, plain.count)
        XCTAssertEqual(sealed.ciphertextBytes, plain.count + 28)
        XCTAssertEqual(sealed.contentHash, VaultCrypto.contentHash(plain))
        let onDisk = try Data(contentsOf: sealedURL)
        XCTAssertEqual(sealed.ciphertextSHA256, sha256Hex(onDisk))
        XCTAssertEqual(try VaultCrypto.open(onDisk, readKey: key, structureKey: nil).plaintext, plain)

        let openedURL = folder.appending(path: "opened.bin")
        let opened = try VaultFileCipher.open(file: sealedURL, to: openedURL, key: key)
        XCTAssertEqual(opened.plaintextBytes, plain.count)
        XCTAssertEqual(try Data(contentsOf: openedURL), plain)

        // One flipped bit anywhere: refused, and nothing is left behind.
        for offset in [5, 1_000_000, onDisk.count - 3] {
            try FileManager.default.copyItem(at: sealedURL, to: folder.appending(path: "bad-\(offset)"))
            try flipByte(at: folder.appending(path: "bad-\(offset)"), offset: offset)
            let out = folder.appending(path: "out-\(offset)")
            XCTAssertThrowsError(try VaultFileCipher.open(file: folder.appending(path: "bad-\(offset)"), to: out, key: key))
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "offset \(offset)")
        }
        // The wrong key is refused the same way.
        let out = folder.appending(path: "wrong-key")
        XCTAssertThrowsError(try VaultFileCipher.open(file: sealedURL, to: out, key: SymmetricKey(size: .bits256)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    // MARK: Staged commits

    struct Made {
        let server: URL
        let key: VaultKey
        let keyText: String
        let vault: SGitVault
        let transport: FolderVaultTransport
        let signer: SoftwareCommitSigner
    }

    func makeVault() async throws -> Made {
        let server = try temporaryFolder("large-server")
        let transport = FolderVaultTransport(root: server)
        let signer = SoftwareCommitSigner()
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: transport)
        let vault = SGitVault(address: VaultAddress(vaultId: created.key.vaultId), readKey: created.key.readKey,
                              cache: temporaryCache(), log: VaultTrafficLog(), transport: transport, branch: "current")
        return Made(server: server, key: created.key, keyText: created.keyText, vault: vault, transport: transport, signer: signer)
    }

    func testStagedLargeFilesAreCommittedAndReadBack() async throws {
        let made = try await makeVault()
        let work = try temporaryFolder("large-work")
        let contents: [String: Data] = [
            "media/five.bin": randomData(5 * 1024 * 1024 + 123),
            "media/nine.bin": randomData(9 * 1024 * 1024 + 7),
            "media/small.bin": randomData(70_000),
            "notes/hello.txt": Data("Written by SGitVault in Swift, beside two large files.\n".utf8),
        ]
        let stager = try await made.vault.stager()
        var staged: [VaultStagedFile] = []
        for (path, data) in contents.sorted(by: { $0.key < $1.key }) {
            let source = work.appending(path: UUID().uuidString)
            try data.write(to: source)
            staged.append(try await stager.stage(file: source, as: path, in: work.appending(path: "staged")))
        }
        XCTAssertEqual(staged.filter(\.large).map(\.path).sorted(), ["media/five.bin", "media/nine.bin"])

        let writeKey = try XCTUnwrap(made.key.writeKey)
        let result = try await made.vault.commit(staged: staged, message: "Add 4 files", signer: made.signer,
                                                 writeKey: writeKey, accessToken: nil, transport: made.transport)
        XCTAssertTrue(result.commit.signature.isVerified, "\(result.commit.signature)")
        XCTAssertEqual(result.commit.message, "Add 4 files")

        // A fresh reader, with an empty cache.
        let reader = SGitVault(address: VaultAddress(vaultId: made.key.vaultId), readKey: made.key.readKey,
                               cache: temporaryCache(), log: VaultTrafficLog(), transport: made.transport, branch: "current")
        let files = try await reader.files()
        XCTAssertEqual(files.map(\.path), contents.keys.sorted())
        XCTAssertEqual(files.filter(\.large).map(\.path), ["media/five.bin", "media/nine.bin"])
        for (path, data) in contents {
            let out = work.appending(path: "out-\(UUID().uuidString)")
            try await reader.download(path, to: out, scratch: work.appending(path: "scratch"), accessToken: nil,
                                      transport: made.transport)
            let got = try Data(contentsOf: out)
            XCTAssertEqual(sha256Hex(got), sha256Hex(data), path)
        }
        // The ordinary reader still opens a large object held in a folder.
        let whole = try await reader.read("media/five.bin")
        XCTAssertEqual(whole, contents["media/five.bin"])

        // What changed, as the history screen shows it.
        let history = try await reader.history(limit: 5)
        let after = try await reader.files(in: history[0])
        let before = try await reader.files(in: history[1])
        XCTAssertEqual(VaultChange.between(before, after).map(\.kind), [.added, .added, .added, .added])

        // A second commit removes one and adds one; the large objects are not sent again.
        let counting = CountingTransport(inner: made.transport)
        let extra = work.appending(path: "extra")
        try Data("second\n".utf8).write(to: extra)
        let more = try await stager.stage(file: extra, as: "notes/second.txt", in: work.appending(path: "staged"))
        let second = try await made.vault.commit(staged: [more], removing: ["media/small.bin"], message: "Add 1 file, remove 1",
                                                 signer: made.signer, writeKey: writeKey, accessToken: nil, transport: counting)
        XCTAssertEqual(second.commit.parents, [result.commit.commitId])
        XCTAssertEqual(counting.largeUploads, 0)
        let now = try await made.vault.files().map(\.path)
        XCTAssertEqual(now, ["media/five.bin", "media/nine.bin", "notes/hello.txt", "notes/second.txt"])
        let nowFiles = try await made.vault.files()
        let changes = VaultChange.between(after, nowFiles)
        XCTAssertEqual(changes.map { "\($0.kind.rawValue) \($0.path)" }, ["removed media/small.bin", "added notes/second.txt"])

        try await export(made, name: "large-swift")
    }

    func testAFailedUploadIsTakenUpWhereItStopped() async throws {
        let made = try await makeVault()
        let work = try temporaryFolder("resume-work")
        let stager = try await made.vault.stager()
        var staged: [VaultStagedFile] = []
        for name in ["a.bin", "b.bin"] {
            let source = work.appending(path: name)
            try randomData(4 * 1024 * 1024 + 4_096).write(to: source)
            staged.append(try await stager.stage(file: source, as: "big/\(name)", in: work.appending(path: "staged")))
        }
        let writeKey = try XCTUnwrap(made.key.writeKey)
        let headBefore = try await made.vault.pull()

        // The second large upload fails: nothing is committed, the first object is recorded as sent.
        let failing = CountingTransport(inner: made.transport, failLargeUploadNumber: 2)
        let sent = Recorder()
        do {
            _ = try await made.vault.commit(staged: staged, message: "Add 2 files", signer: made.signer, writeKey: writeKey,
                                            accessToken: nil, transport: failing, uploaded: { sent.add($0) })
            XCTFail("expected the upload to fail")
        } catch {}
        XCTAssertEqual(sent.values, [staged[0].blobId])
        let headAfterFailure = try await made.vault.pull()
        XCTAssertEqual(headAfterFailure.commitId, headBefore.commitId)

        // Again, saying what is already there: only the second object travels.
        let retry = CountingTransport(inner: made.transport)
        let result = try await made.vault.commit(staged: staged, message: "Add 2 files", signer: made.signer, writeKey: writeKey,
                                                 accessToken: nil, transport: retry, alreadyUploaded: Set(sent.values))
        XCTAssertEqual(retry.largeUploads, 1)
        XCTAssertTrue(result.commit.signature.isVerified)
        let paths = try await made.vault.files().map(\.path)
        XCTAssertEqual(paths, ["big/a.bin", "big/b.bin"])
    }

    func testALostRaceOverwritesNothingAndTheSameFilesGoInOnTheNextTry() async throws {
        let made = try await makeVault()
        let work = try temporaryFolder("race-work")
        let writeKey = try XCTUnwrap(made.key.writeKey)
        let stager = try await made.vault.stager()
        let source = work.appending(path: "mine.txt")
        try Data("mine\n".utf8).write(to: source)
        let mine = try await stager.stage(file: source, as: "mine.txt", in: work.appending(path: "staged"))

        // Somebody else commits between our read of the ref and our write of it.
        let other = SGitVault(address: VaultAddress(vaultId: made.key.vaultId), readKey: made.key.readKey,
                              cache: temporaryCache(), log: VaultTrafficLog(), transport: made.transport, branch: "current")
        let folder = made.transport
        let racing = InterleavingTransport(inner: folder) {
            _ = try await other.commit(["theirs.txt": Data("theirs\n".utf8)], message: "Theirs", branch: "current",
                                       signer: SoftwareCommitSigner(), writeKey: writeKey, accessToken: nil,
                                       writer: folder)
        }
        do {
            _ = try await made.vault.commit(staged: [mine], message: "Add mine.txt", signer: made.signer, writeKey: writeKey,
                                            accessToken: nil, transport: racing)
            XCTFail("expected a push conflict")
        } catch VaultError.pushConflict(let branch) {
            XCTAssertEqual(branch, "current")
        }
        let afterRace = try await other.files().map(\.path)
        XCTAssertEqual(afterRace, ["theirs.txt"])

        // The same staged file, committed again, lands on top of theirs. Both are there.
        let result = try await made.vault.commit(staged: [mine], message: "Add mine.txt", signer: made.signer, writeKey: writeKey,
                                                 accessToken: nil, transport: made.transport, alreadyUploaded: [mine.blobId])
        XCTAssertEqual(result.commit.message, "Add mine.txt")
        let paths = try await made.vault.files().map(\.path)
        XCTAssertEqual(paths, ["mine.txt", "theirs.txt"])
    }

    func testAVaultWithLargeFilesIsMovedToAnotherPlace() async throws {
        let made = try await makeVault()
        let work = try temporaryFolder("move-work")
        let stager = try await made.vault.stager()
        let big = randomData(6 * 1024 * 1024 + 3)
        let source = work.appending(path: "big.bin")
        try big.write(to: source)
        let small = work.appending(path: "small.txt")
        try Data("small\n".utf8).write(to: small)
        let staged = [try await stager.stage(file: source, as: "media/big.bin", in: work.appending(path: "staged")),
                      try await stager.stage(file: small, as: "small.txt", in: work.appending(path: "staged"))]
        let writeKey = try XCTUnwrap(made.key.writeKey)
        _ = try await made.vault.commit(staged: staged, message: "Add 2 files", signer: made.signer, writeKey: writeKey,
                                        accessToken: nil, transport: made.transport)

        // To a place that does not hold the vault: everything goes, the large object as a file.
        let elsewhere = CountingTransport(inner: FolderVaultTransport(root: try temporaryFolder("move-server")))
        let result = try await VaultSync.transferWithLargeFiles(key: made.key, from: made.transport, to: elsewhere,
                                                                accessToken: nil, scratch: work.appending(path: "scratch"))
        XCTAssertEqual(result.outcome, .created)
        XCTAssertEqual(elsewhere.largeUploads, 1)
        let reader = SGitVault(address: VaultAddress(vaultId: made.key.vaultId), readKey: made.key.readKey,
                               cache: temporaryCache(), log: VaultTrafficLog(), transport: elsewhere.inner, branch: "current")
        let head = try await reader.pull()
        XCTAssertTrue(head.signature.isVerified)
        let out = work.appending(path: "out.bin")
        try await reader.download("media/big.bin", to: out, scratch: work.appending(path: "scratch2"), accessToken: nil,
                                  transport: elsewhere.inner)
        XCTAssertEqual(try Data(contentsOf: out), big)

        // Again: nothing to send. Then one more commit: a fast-forward that sends no large object twice.
        let again = try await VaultSync.transferWithLargeFiles(key: made.key, from: made.transport, to: elsewhere,
                                                               accessToken: nil, scratch: work.appending(path: "scratch"))
        XCTAssertEqual(again.outcome, .upToDate)
        _ = try await made.vault.commit(staged: [], removing: ["small.txt"], message: "Remove small.txt", signer: made.signer,
                                        writeKey: writeKey, accessToken: nil, transport: made.transport)
        let forward = try await VaultSync.transferWithLargeFiles(key: made.key, from: made.transport, to: elsewhere,
                                                                 accessToken: nil, scratch: work.appending(path: "scratch"))
        XCTAssertEqual(forward.outcome, .fastForwarded)
        XCTAssertEqual(elsewhere.largeUploads, 1)
    }

    func testMediaTypes() {
        XCTAssertEqual(VaultBlobStager.contentType(for: "a/IMG_0001.HEIC"), "image/heic")
        XCTAssertEqual(VaultBlobStager.contentType(for: "clip.mov"), "video/quicktime")
        XCTAssertEqual(VaultBlobStager.contentType(for: "clip.mp4"), "video/mp4")
        XCTAssertEqual(VaultBlobStager.contentType(for: "photo.jpg"), "image/jpeg")
        XCTAssertEqual(VaultBlobStager.contentType(for: "unknown.xyz"), "application/octet-stream")
    }

    func testThePresignedRouteIsRecognisedAsMissing() {
        XCTAssertTrue(HTTPVaultTransport.presignedUnavailable(status: 400, body: Data(#"{"detail":"S3 storage mode required"}"#.utf8)))
        XCTAssertTrue(HTTPVaultTransport.presignedUnavailable(status: 404, body: Data()))
        XCTAssertTrue(HTTPVaultTransport.presignedUnavailable(status: 501, body: Data()))
        XCTAssertTrue(HTTPVaultTransport.presignedUnavailable(status: 500, body: Data("presigned_not_available".utf8)))
        XCTAssertFalse(HTTPVaultTransport.presignedUnavailable(status: 500, body: Data("boom".utf8)))
        XCTAssertFalse(HTTPVaultTransport.presignedUnavailable(status: 503, body: Data()))
    }

    func testOnlyHttpsSignedURLsAreFollowed() {
        let live = HTTPVaultTransport(server: URL(string: "https://dev.send.sgraph.ai")!)
        XCTAssertTrue(live.allowsSigned(URL(string: "https://bucket.s3.amazonaws.com/x?sig=1")!))
        XCTAssertFalse(live.allowsSigned(URL(string: "http://bucket.s3.amazonaws.com/x")!))
        XCTAssertFalse(live.allowsSigned(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(live.allowsSigned(URL(string: "http://dev.send.sgraph.ai/x")!))
        XCTAssertTrue(live.allowsSigned(URL(string: "http://127.0.0.1:8080/x")!))
        let lan = HTTPVaultTransport(server: URL(string: "http://nas.local:8080")!)
        XCTAssertTrue(lan.allowsSigned(URL(string: "http://nas.local:9000/x")!))
        XCTAssertFalse(lan.allowsSigned(URL(string: "http://elsewhere.local/x")!))
    }

    // MARK: Against sgit

    /// What sgit wrote (sgit_writes_large.py, run on Linux by CI), read here.
    func testSwiftReadsTheLargeFilesSgitWrote() async throws {
        guard let folder = ProcessInfo.processInfo.environment["SGITVAULT_SGIT_WROTE"], !folder.isEmpty else {
            throw XCTSkip("SGITVAULT_SGIT_WROTE is not set: CI sets it to the vault sgit wrote")
        }
        struct Expected: Decodable {
            struct File: Decodable { let size: Int; let sha256: String }
            let vault_id: String
            let read_key_hex: String
            let messages: [String]
            let files: [String: File]
        }
        let root = URL(fileURLWithPath: folder).appending(path: "large", directoryHint: .isDirectory)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: root.appending(path: "expected.json")))
        let transport = FolderVaultTransport(root: root.appending(path: "server", directoryHint: .isDirectory))
        let vault = SGitVault(address: VaultAddress(vaultId: expected.vault_id),
                              readKey: SymmetricKey(data: try XCTUnwrap(Data(hexString: expected.read_key_hex))),
                              cache: temporaryCache(), log: VaultTrafficLog(), transport: transport, branch: "current")
        let head = try await vault.pull()
        XCTAssertTrue(head.signature.isVerified, "\(head.signature)")
        let history = try await vault.history(limit: 10)
        XCTAssertEqual(history.map(\.message), expected.messages)
        let files = try await vault.files()
        XCTAssertEqual(files.map(\.path), expected.files.keys.sorted())
        XCTAssertEqual(files.filter(\.large).count, expected.files.values.filter { $0.size > 4 * 1024 * 1024 }.count,
                       "sgit flags every blob over 4 MB as large")
        let work = try temporaryFolder("sgit-wrote")
        for (path, want) in expected.files {
            let out = work.appending(path: UUID().uuidString)
            try await vault.download(path, to: out, scratch: work.appending(path: "scratch"), accessToken: nil, transport: transport)
            XCTAssertEqual(try VaultFileCipher.byteCount(of: out), want.size, path)
            XCTAssertEqual(try VaultFileCipher.sha256(of: out), want.sha256, path)
        }
    }

    /// Write the vault (as the server holds it) and what sgit should find, for the Linux read-back job.
    func export(_ made: Made, name: String) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: made.server, to: dest.appending(path: "server"))
        let reader = SGitVault(address: VaultAddress(vaultId: made.key.vaultId), readKey: made.key.readKey,
                               cache: temporaryCache(), log: VaultTrafficLog(), transport: made.transport, branch: "current")
        var files: [String: [String: Any]] = [:]
        for file in try await reader.files() {
            let data = try await reader.read(file.path)
            files[file.path] = ["size": data.count, "sha256": sha256Hex(data)]
        }
        let messages = try await reader.history(limit: 20).map(\.message)
        let expected: [String: Any] = [
            "WARNING": "THROWAWAY key, made by a test for this run only. This vault exists on no server.",
            "vault_key": made.keyText, "vault_id": made.key.vaultId,
            "branch": "current", "files": files, "messages": messages,
        ]
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
            .write(to: dest.appending(path: "expected.json"))
    }
}

/// Collects values from a `@Sendable` callback.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String] = []
    func add(_ value: String) {
        lock.lock()
        held.append(value)
        lock.unlock()
    }
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return held
    }
}

/// A folder transport that counts large uploads and can fail the nth.
final class CountingTransport: VaultTransport, VaultWriteTransport, VaultLargeTransport, @unchecked Sendable {
    var label: String { inner.label }

    func get(vaultId: String, path: String) async throws -> VaultResponse {
        try await inner.get(vaultId: vaultId, path: path)
    }

    struct Failed: Error {}
    let inner: FolderVaultTransport
    let failLargeUploadNumber: Int?
    private let lock = NSLock()
    private var count = 0

    init(inner: FolderVaultTransport, failLargeUploadNumber: Int? = nil) {
        self.inner = inner
        self.failLargeUploadNumber = failLargeUploadNumber
    }

    var largeUploads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    private func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        try await inner.batch(vaultId: vaultId, writeKey: writeKey, accessToken: accessToken, operations: operations)
    }

    func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                     progress: @escaping @Sendable (Int) -> Void) async throws {
        if next() == failLargeUploadNumber { throw Failed() }
        try await inner.uploadLarge(vaultId: vaultId, fileId: fileId, from: file, writeKey: writeKey,
                                    accessToken: accessToken, progress: progress)
    }

    func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                       progress: @escaping @Sendable (Int) -> Void) async throws {
        try await inner.downloadLarge(vaultId: vaultId, fileId: fileId, to: file, expectedBytes: expectedBytes,
                                      accessToken: accessToken, progress: progress)
    }
}

/// A folder transport that lets another writer in just before the first compare-and-swap.
final class InterleavingTransport: VaultWriteTransport, VaultLargeTransport, @unchecked Sendable {
    let inner: FolderVaultTransport
    let other: @Sendable () async throws -> Void
    private let lock = NSLock()
    private var fired = false

    init(inner: FolderVaultTransport, other: @escaping @Sendable () async throws -> Void) {
        self.inner = inner
        self.other = other
    }

    private func shouldFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }

    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        if operations.contains(where: { $0.op == .writeIfMatch }), shouldFire() { try await other() }
        return try await inner.batch(vaultId: vaultId, writeKey: writeKey, accessToken: accessToken, operations: operations)
    }

    func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                     progress: @escaping @Sendable (Int) -> Void) async throws {
        try await inner.uploadLarge(vaultId: vaultId, fileId: fileId, from: file, writeKey: writeKey,
                                    accessToken: accessToken, progress: progress)
    }

    func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                       progress: @escaping @Sendable (Int) -> Void) async throws {
        try await inner.downloadLarge(vaultId: vaultId, fileId: fileId, to: file, expectedBytes: expectedBytes,
                                      accessToken: accessToken, progress: progress)
    }
}
