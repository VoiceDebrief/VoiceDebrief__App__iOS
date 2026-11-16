import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// A vault as one file (SGit Secrets, step 1): the archive round trip and its refusals, the union of two
/// copies that changed apart, and one file replaced with five earlier copies kept. The archive is exported
/// (when SGITVAULT_ROUNDTRIP_OUT is set) so CI can unzip it with `unzip` and have sgit clone it.
@MainActor
final class FileStoreTests: XCTestCase {
    func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sgitvault-\(name)-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func open(_ key: VaultKey, in folder: URL) -> SGitVault {
        SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: temporaryCache(),
                  log: VaultTrafficLog(), transport: FolderVaultTransport(root: folder), branch: "current")
    }

    func localVault(signer: SoftwareCommitSigner) async throws -> (created: VaultCreated, folder: URL) {
        let device = try folder("device")
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: FolderVaultTransport(root: device))
        try await commit(["secrets/wifi.json": Data("{\"name\":\"Office Wi-Fi\"}\n".utf8)], "Add Wi-Fi",
                         created.key, in: device, signer: signer)
        return (created, device)
    }

    @discardableResult
    func commit(_ changes: [String: Data?], _ message: String, _ key: VaultKey, in folder: URL,
                signer: SoftwareCommitSigner) async throws -> VaultPushResult {
        try await open(key, in: folder).commit(changes, message: message, branch: "current", signer: signer,
                                                writeKey: try XCTUnwrap(key.writeKey), accessToken: nil,
                                                writer: FolderVaultTransport(root: folder))
    }

    func names(_ folder: URL, _ sub: String) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: sub).path)) ?? [])
    }

    func assertRefused(_ data: Data, _ expected: (VaultArchiveError) -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try VaultArchive.entries(data), file: file, line: line) { error in
            guard let error = error as? VaultArchiveError else { return XCTFail("\(error)", file: file, line: line) }
            XCTAssertTrue(expected(error), "\(error)", file: file, line: line)
        }
    }

    // MARK: The archive

    func testAVaultSurvivesTheRoundTripThroughOneFile() async throws {
        let signer = SoftwareCommitSigner()
        let (created, device) = try await localVault(signer: signer)
        let archive = try VaultArchive.archive(folder: device)
        XCTAssertEqual(try VaultArchive.archive(folder: device), archive, "the same folder gives the same bytes")

        let unpacked = try folder("unpacked")
        let written = try VaultArchive.read(archive, into: unpacked)
        XCTAssertTrue(written.allSatisfy { $0.hasPrefix("bare/") })
        for sub in VaultArchive.folders { XCTAssertEqual(names(unpacked, sub), names(device, sub), sub) }

        let reader = open(created.key, in: unpacked)
        let head = try await reader.pull()
        let original = try await open(created.key, in: device).pull()
        XCTAssertEqual(head.commitId, original.commitId)
        let wifi = try await reader.read("secrets/wifi.json")
        XCTAssertEqual(wifi, Data("{\"name\":\"Office Wi-Fi\"}\n".utf8))

        try await export(created: created, archive: archive, reader: reader, name: "archived")
    }

    func testUnpackingRefusesAFolderThatHoldsFiles() async throws {
        let (_, device) = try await localVault(signer: SoftwareCommitSigner())
        let archive = try VaultArchive.archive(folder: device)
        XCTAssertThrowsError(try VaultArchive.read(archive, into: device)) { error in
            XCTAssertEqual(error as? VaultArchiveError, .destinationNotEmpty(device.lastPathComponent))
        }
    }

    func testAChangedByteIsCaught() async throws {
        let (_, device) = try await localVault(signer: SoftwareCommitSigner())
        var archive = try VaultArchive.archive(folder: device)
        let first = try XCTUnwrap(try VaultArchive.entries(archive).first)
        XCTAssertFalse(first.data.isEmpty)
        let lastByteOfFirstEntry = 30 + first.name.utf8.count + first.data.count - 1
        archive[lastByteOfFirstEntry] ^= 0x01
        assertRefused(archive) { $0 == .damaged(first.name) }
    }

    func testAnObjectThatDoesNotMatchItsIdIsRefusedEvenWithAGoodChecksum() throws {
        let data = Data("not what the id says".utf8)
        let wrongId = VaultCrypto.objectId(of: Data("something else".utf8))
        let archive = try VaultArchive.zip([.init(name: "bare/data/\(wrongId)", data: data)])
        assertRefused(archive) { $0 == .integrity(wrongId) }
        let rightId = VaultCrypto.objectId(of: data)
        XCTAssertEqual(try VaultArchive.entries(try VaultArchive.zip([.init(name: "bare/data/\(rightId)", data: data)])).count, 1)
    }

    func testNamesThatCouldEscapeTheFolderAreRefused() throws {
        let hostile = [
            "../outside", "/etc/passwd", "bare/data/../../outside", "bare/data/../refs/x", "bare/data/./x",
            "bare\\data\\x", "bare/data/a\\b", "bare/data/a\0b", "bare/data/", "bare/data//x", "other/data/x",
            "bare/secrets/x", "bare/data/sub/x", "bare/data/.hidden", "bare/data/x y", "bare/data",
        ]
        for name in hostile {
            // The internal writer does not check names, so it can build what an attacker would.
            let archive = try VaultArchive.zip([.init(name: name, data: Data())])
            assertRefused(archive) { error in
                if case .unsafeName = error { return true }
                return false
            }
        }
    }

    func testSymbolicLinksAndFoldersAreRefused() throws {
        let link = try VaultArchive.zip([.init(name: "bare/refs/x", data: Data("/etc/passwd".utf8), mode: 0o120777)])
        assertRefused(link) { $0 == .unsupportedEntry("bare/refs/x") }
        let directory = try VaultArchive.zip([.init(name: "bare/refs/x", data: Data(), mode: 0o040755)])
        assertRefused(directory) { $0 == .unsupportedEntry("bare/refs/x") }
    }

    func testTheSameNameTwiceIsRefused() throws {
        let twice = try VaultArchive.zip([.init(name: "bare/refs/x", data: Data("a".utf8)),
                                          .init(name: "bare/refs/x", data: Data("b".utf8))])
        assertRefused(twice) { $0 == .duplicateName("bare/refs/x") }
    }

    func testTheChecksumMatchesTheStandard() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    // MARK: The union

    func testTwoCopiesThatChangedApartJoinByUnion() async throws {
        let signer = SoftwareCommitSigner()
        let (created, iphone) = try await localVault(signer: signer)
        let ipad = try folder("ipad")
        _ = try VaultArchive.read(try VaultArchive.archive(folder: iphone), into: ipad)
        let iphoneSigner = SoftwareCommitSigner(), ipadSigner = SoftwareCommitSigner()
        let a = try await commit(["secrets/bank.json": Data("{}\n".utf8)], "Add bank (iPhone)", created.key, in: iphone, signer: iphoneSigner)
        let b = try await commit(["secrets/router.json": Data("{}\n".utf8)], "Add router (iPad)", created.key, in: ipad, signer: ipadSigner)
        let refsBefore = try FileManager.default.contentsOfDirectory(atPath: iphone.appending(path: "bare/refs").path).sorted()
            .map { try Data(contentsOf: iphone.appending(path: "bare/refs/\($0)")) }

        let union = try VaultObjects.union(from: ipad, into: iphone)
        XCTAssertTrue(union.added.contains("bare/data/\(b.commit.commitId)"))
        XCTAssertTrue(union.differing.isEmpty)
        XCTAssertTrue(names(iphone, "bare/data").isSuperset(of: names(ipad, "bare/data")))
        XCTAssertTrue(names(iphone, "bare/data").contains(a.commit.commitId))
        let refsAfter = try FileManager.default.contentsOfDirectory(atPath: iphone.appending(path: "bare/refs").path).sorted()
            .map { try Data(contentsOf: iphone.appending(path: "bare/refs/\($0)")) }
        XCTAssertEqual(refsAfter, refsBefore, "refs are a merge's job, not the union's")

        let again = try VaultObjects.union(from: ipad, into: iphone)
        XCTAssertEqual(again.added, [])
    }

    func testATamperedSourceChangesNothing() async throws {
        let signer = SoftwareCommitSigner()
        let (created, device) = try await localVault(signer: signer)
        let other = try folder("other")
        _ = try VaultArchive.read(try VaultArchive.archive(folder: device), into: other)
        let result = try await commit(["new.md": Data("new\n".utf8)], "Elsewhere", created.key, in: other, signer: signer)
        try flipByte(at: other.appending(path: "bare/data/\(result.commit.commitId)"), offset: 20)
        let before = names(device, "bare/data")
        XCTAssertThrowsError(try VaultObjects.union(from: other, into: device)) { error in
            XCTAssertEqual(error as? VaultArchiveError, .integrity(result.commit.commitId))
        }
        XCTAssertEqual(names(device, "bare/data"), before)
    }

    // MARK: The file store

    func testReplacingKeepsFiveEarlierCopiesInTheFilesOwnFolderOnly() throws {
        let parent = try folder("icloud")
        let store = VaultFileStore(file: parent.appending(path: "My secrets.sgvault"), keep: 5, device: "Owner's iPhone")
        let neighbour = VaultFileStore(file: parent.appending(path: "My secrets 2.sgvault"), keep: 5, device: "iPad")
        try neighbour.replace(with: Data("n1".utf8))
        try neighbour.replace(with: Data("n2".utf8))
        let stray = parent.appending(path: ".versions/2020-01-01T00-00-00Z other.sgvault")
        try Data("not ours".utf8).write(to: stray)

        let start = Date(timeIntervalSince1970: 1_763_247_000)
        for n in 1...8 { try store.replace(with: Data("v\(n)".utf8), at: start.addingTimeInterval(Double(n))) }

        XCTAssertEqual(try store.read(), Data("v8".utf8))
        let copies = try store.earlierCopies()
        XCTAssertEqual(copies.count, 5)
        XCTAssertEqual(try copies.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }, ["v3", "v4", "v5", "v6", "v7"])
        XCTAssertTrue(copies.allSatisfy { $0.lastPathComponent.hasSuffix(" Owner-s-iPhone.sgvault") })
        XCTAssertEqual(try neighbour.earlierCopies().count, 1, "another file's copies are not touched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path), "a file the store did not write is not touched")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: parent.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [])
    }

    func testTwoCopiesInTheSameSecondBothSurvive() throws {
        let parent = try folder("same-second")
        let store = VaultFileStore(file: parent.appending(path: "v.sgvault"), device: "Mac")
        let moment = Date(timeIntervalSince1970: 1_763_247_000)
        for n in 1...3 { try store.replace(with: Data("v\(n)".utf8), at: moment) }
        XCTAssertEqual(try store.earlierCopies().count, 2)
    }

    func testAFileThatIsNotThereReadsAsNil() throws {
        let store = VaultFileStore(file: try folder("empty").appending(path: "none.sgvault"), device: "Mac")
        XCTAssertNil(try store.read())
    }

    // MARK: Helpers

    /// The archive and what sgit should find in it, for the Linux read-back job.
    func export(created: VaultCreated, archive: Data, reader: SGitVault, name: String) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try archive.write(to: dest.appending(path: "vault.sgvault"))
        var files: [String: [String: Any]] = [:]
        for file in try await reader.files() {
            let data = try await reader.read(file.path)
            files[file.path] = ["size": data.count, "sha256": sha256Hex(data)]
        }
        let messages = try await reader.history(limit: 20).map(\.message)
        let expected: [String: Any] = [
            "WARNING": "A THROWAWAY vault key made by a test. The vault exists on no server.",
            "vault_key": created.keyText, "vault_id": created.key.vaultId,
            "branch": "current", "files": files, "messages": messages,
        ]
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
            .write(to: dest.appending(path: "expected.json"))
    }
}
