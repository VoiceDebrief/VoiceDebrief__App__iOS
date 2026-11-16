import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// Merging two heads (SGit Secrets, step 2). An iPhone and an iPad hold copies of one vault and change them
/// apart; the objects are joined with `VaultObjects.union`, then `merge(theirs:)` joins the heads. A merged
/// vault is exported (when SGITVAULT_ROUNDTRIP_OUT is set) so CI can have sgit check its signatures and files.
@MainActor
final class MergeTests: XCTestCase {
    let wifi = "secrets/wifi.json"

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

    @discardableResult
    func commit(_ changes: [String: Data?], _ message: String, _ key: VaultKey, in folder: URL,
                signer: SoftwareCommitSigner) async throws -> VaultCommit {
        try await open(key, in: folder).commit(changes, message: message, branch: "current", signer: signer,
                                                writeKey: try XCTUnwrap(key.writeKey), accessToken: nil,
                                                writer: FolderVaultTransport(root: folder)).commit
    }

    struct Pair {
        let created: VaultCreated
        let iphone: URL, ipad: URL
        let iphoneSigner = SoftwareCommitSigner(), ipadSigner = SoftwareCommitSigner()
        var key: VaultKey { created.key }
    }

    /// One vault with the Wi-Fi secret, copied to a second device through the one-file archive.
    func pair() async throws -> Pair {
        let iphone = try folder("iphone")
        let signer = SoftwareCommitSigner()
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: FolderVaultTransport(root: iphone))
        try await commit([wifi: Data("{\"password\":\"original\"}\n".utf8)], "Add Wi-Fi", created.key, in: iphone, signer: signer)
        let ipad = try folder("ipad")
        try VaultArchive.read(try VaultArchive.archive(folder: iphone), into: ipad)
        return Pair(created: created, iphone: iphone, ipad: ipad)
    }

    /// Joins the iPad's head into the iPhone's copy.
    func mergeIPadIntoIPhone(_ p: Pair, ipadHead: String) async throws -> VaultMergeResult {
        try VaultObjects.union(from: p.ipad, into: p.iphone)
        return try await open(p.key, in: p.iphone).merge(theirs: ipadHead, signer: p.iphoneSigner,
                                                         writeKey: try XCTUnwrap(p.key.writeKey), accessToken: nil,
                                                         writer: FolderVaultTransport(root: p.iphone))
    }

    func contents(_ key: VaultKey, in folder: URL) async throws -> [String: String] {
        let vault = open(key, in: folder)
        var out: [String: String] = [:]
        for file in try await vault.files() { out[file.path] = String(decoding: try await vault.read(file.path), as: UTF8.self) }
        return out
    }

    func pause() async throws { try await Task.sleep(for: .milliseconds(20)) }   // distinct commit times

    // MARK: Tests

    func testDifferentSecretsMergeWithNoQuestion() async throws {
        let p = try await pair()
        let mine = try await commit(["secrets/bank.json": Data("bank\n".utf8)], "Add bank (iPhone)", p.key, in: p.iphone, signer: p.iphoneSigner)
        let theirs = try await commit(["secrets/router.json": Data("router\n".utf8)], "Add router (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)

        let result = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        XCTAssertEqual(result.kind, .merged)
        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(result.takenFromTheirs, ["secrets/router.json"])
        XCTAssertEqual(result.head.parents, [mine.commitId, theirs.commitId])
        XCTAssertTrue(result.head.signature.isVerified)
        let files = try await contents(p.key, in: p.iphone)
        XCTAssertEqual(Set(files.keys), [wifi, "secrets/bank.json", "secrets/router.json"])
        try await export(p, name: "merged")
    }

    /// The case the conductor asked for: both devices changed the same secret. The newer change stays at the
    /// path; the older is kept beside it under a conflict name; nothing is lost and the merge says so.
    func testTheSameSecretChangedOnBothKeepsTheNewerChangeAndTheOtherBeside() async throws {
        let p = try await pair()
        let older = try await commit([wifi: Data("{\"password\":\"from-iphone\"}\n".utf8)], "Change Wi-Fi (iPhone, 09:00)",
                                     p.key, in: p.iphone, signer: p.iphoneSigner)
        try await pause()
        let newer = try await commit([wifi: Data("{\"password\":\"from-ipad\"}\n".utf8)], "Change Wi-Fi (iPad, 09:30)",
                                     p.key, in: p.ipad, signer: p.ipadSigner)
        XCTAssertGreaterThan(newer.timestamp, older.timestamp)

        let result = try await mergeIPadIntoIPhone(p, ipadHead: newer.commitId)
        let conflictPath = "secrets/wifi.conflict-\(older.commitId.suffix(8)).json"
        XCTAssertEqual(result.conflicts, [VaultMergeConflict(path: wifi, keptFrom: newer.commitId,
                                                             otherCopyPath: conflictPath, otherFrom: older.commitId)])
        let files = try await contents(p.key, in: p.iphone)
        XCTAssertEqual(files[wifi], "{\"password\":\"from-ipad\"}\n", "the newer change (the iPad's) wins")
        XCTAssertEqual(files[conflictPath], "{\"password\":\"from-iphone\"}\n", "the older is kept, not lost")
        XCTAssertTrue(result.head.message.contains("1 conflict"))
    }

    func testTheNewerChangeWinsWhicheverSideItIsOnAndBothDevicesAgree() async throws {
        let p = try await pair()
        let ipadChange = try await commit([wifi: Data("ipad\n".utf8)], "Change Wi-Fi (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)
        try await pause()
        let iphoneChange = try await commit([wifi: Data("iphone\n".utf8)], "Change Wi-Fi (iPhone)", p.key, in: p.iphone, signer: p.iphoneSigner)
        // Each device gets the other's objects, then each merges the other's head on its own.
        try VaultObjects.union(from: p.ipad, into: p.iphone)
        try VaultObjects.union(from: p.iphone, into: p.ipad)
        let onIPhone = try await open(p.key, in: p.iphone).merge(theirs: ipadChange.commitId, signer: p.iphoneSigner,
                                                                 writeKey: try XCTUnwrap(p.key.writeKey), accessToken: nil,
                                                                 writer: FolderVaultTransport(root: p.iphone))
        let onIPad = try await open(p.key, in: p.ipad).merge(theirs: iphoneChange.commitId, signer: p.ipadSigner,
                                                             writeKey: try XCTUnwrap(p.key.writeKey), accessToken: nil,
                                                             writer: FolderVaultTransport(root: p.ipad))
        XCTAssertEqual(onIPhone.conflicts.first?.keptFrom, iphoneChange.commitId, "ours is newer here, so ours stays")
        XCTAssertEqual(onIPad.conflicts.first?.keptFrom, iphoneChange.commitId)
        let iphoneFiles = try await contents(p.key, in: p.iphone)
        let ipadFiles = try await contents(p.key, in: p.ipad)
        XCTAssertEqual(iphoneFiles, ipadFiles, "two devices merging the same heads arrive at the same files")
        XCTAssertEqual(iphoneFiles[wifi], "iphone\n")
    }

    func testAChangeIsKeptOverADeletion() async throws {
        let p = try await pair()
        try await commit([wifi: nil], "Delete Wi-Fi (iPhone)", p.key, in: p.iphone, signer: p.iphoneSigner)
        let theirs = try await commit([wifi: Data("changed\n".utf8)], "Change Wi-Fi (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)
        let result = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        XCTAssertEqual(result.keptOverDeletion, [wifi])
        let files = try await contents(p.key, in: p.iphone)
        XCTAssertEqual(files[wifi], "changed\n")
    }

    func testADeletionOnOneSideOnlyIsTaken() async throws {
        let p = try await pair()
        try await commit(["secrets/bank.json": Data("bank\n".utf8)], "Add bank (iPhone)", p.key, in: p.iphone, signer: p.iphoneSigner)
        let theirs = try await commit([wifi: nil], "Delete Wi-Fi (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)
        let result = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        XCTAssertEqual(result.takenFromTheirs, [wifi])
        let files = try await contents(p.key, in: p.iphone)
        XCTAssertEqual(Set(files.keys), ["secrets/bank.json"])
    }

    func testACopyThatWasBehindIsBroughtLevelWithoutRewritingHistory() async throws {
        let p = try await pair()
        let before = try await open(p.key, in: p.iphone).pull()
        let theirs = try await commit(["secrets/router.json": Data("router\n".utf8)], "Add router (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)
        let result = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        XCTAssertEqual(result.kind, .merged)
        XCTAssertEqual(result.base, before.commitId)
        XCTAssertEqual(result.head.parents, [before.commitId, theirs.commitId])
        let iphoneFiles = try await contents(p.key, in: p.iphone)
        let ipadFiles = try await contents(p.key, in: p.ipad)
        XCTAssertEqual(iphoneFiles, ipadFiles)
    }

    func testAHeadAlreadyInTheHistoryIsUpToDate() async throws {
        let p = try await pair()
        let theirs = try await commit(["secrets/router.json": Data("router\n".utf8)], "Add router (iPad)", p.key, in: p.ipad, signer: p.ipadSigner)
        let first = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        let again = try await mergeIPadIntoIPhone(p, ipadHead: theirs.commitId)
        XCTAssertEqual(again.kind, .upToDate)
        XCTAssertEqual(again.head.commitId, first.head.commitId)
    }

    /// The other direction: a merge that sgit itself wrote (Tests/Fixtures/merge, made by generate_fixtures.py
    /// with sgit-ai 0.27.0) is read by Swift: the head has two parents, both sides' changes are there (an
    /// addition on each side and a deletion on one), and every commit's signature verifies.
    func testSwiftReadsAMergeThatSgitWrote() async throws {
        struct Expected: Decodable {
            let vault_key: String
            let files: [String: Fixture.FileExpectation]
            let messages_include: [String]
        }
        let dir = Fixture.root.appending(path: "merge", directoryHint: .isDirectory)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appending(path: "expected.json")))
        let key = try await SGitVault.deriveKey(from: expected.vault_key, log: VaultTrafficLog())
        let vault = SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: temporaryCache(),
                              log: VaultTrafficLog(), transport: FolderVaultTransport(root: dir.appending(path: "server")),
                              branch: "current")
        let head = try await vault.pull()
        XCTAssertEqual(head.parents.count, 2, "sgit's merge commit has two parents")
        XCTAssertTrue(head.signature.isVerified)
        let files = try await vault.files()
        XCTAssertEqual(Set(files.map(\.path)), Set(expected.files.keys))
        for (path, want) in expected.files {
            let data = try await vault.read(path)
            XCTAssertEqual(data.count, want.size, path)
            XCTAssertEqual(sha256Hex(data), want.sha256, path)
        }
        let history = try await vault.history(limit: 20)
        let messages = history.map(\.message)
        for message in expected.messages_include { XCTAssertTrue(messages.contains(message), message) }
        XCTAssertTrue(history.allSatisfy { $0.signature.isVerified || $0.parents.isEmpty }, "every commit verifies (the first may be unsigned)")
    }

    func testConflictNamesKeepTheExtension() {
        XCTAssertEqual(SGitVault.conflictPath(for: "secrets/abc.json", commitId: "obj-cas-imm-0123456789ab"),
                       "secrets/abc.conflict-456789ab.json")
        XCTAssertEqual(SGitVault.conflictPath(for: "notes/README", commitId: "obj-cas-imm-0123456789ab"),
                       "notes/README.conflict-456789ab")
        XCTAssertEqual(SGitVault.conflictPath(for: "a.b/.hidden", commitId: "obj-cas-imm-0123456789ab"),
                       "a.b/.hidden.conflict-456789ab")
    }

    // MARK: Export

    /// The merged vault and what sgit should find, for the Linux read-back job (signatures include the merge commit).
    func export(_ p: Pair, name: String) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: p.iphone, to: dest.appending(path: "server"))
        let reader = open(p.key, in: p.iphone)
        var files: [String: [String: Any]] = [:]
        for file in try await reader.files() {
            let data = try await reader.read(file.path)
            files[file.path] = ["size": data.count, "sha256": sha256Hex(data)]
        }
        let messages = try await reader.history(limit: 20).map(\.message)
        let expected: [String: Any] = [
            "WARNING": "A THROWAWAY vault key made by a test. The vault exists on no server.",
            "vault_key": p.created.keyText, "vault_id": p.key.vaultId,
            "branch": "current", "files": files, "messages": messages,
        ]
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
            .write(to: dest.appending(path: "expected.json"))
    }
}
