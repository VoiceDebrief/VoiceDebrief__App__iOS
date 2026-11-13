import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// A vault made in a folder (as on a device), then pushed to another folder (as to a server) and pulled
/// back: local first, a server as a remote. The pushed folder is exported (when SGITVAULT_ROUNDTRIP_OUT
/// is set) so CI can have sgit itself clone what was created locally and then pushed.
@MainActor
final class SyncTests: XCTestCase {
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

    func head(_ key: VaultKey, in folder: URL) async throws -> String {
        try await open(key, in: folder).pull().commitId
    }

    /// A vault in a new folder with one commit after its creation.
    func localVault(signer: SoftwareCommitSigner) async throws -> (created: VaultCreated, folder: URL) {
        let device = try folder("device")
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: FolderVaultTransport(root: device))
        try await commit(["README.md": Data("# Made on a device\n".utf8)], "First note", created.key, in: device, signer: signer)
        return (created, device)
    }

    @discardableResult
    func commit(_ changes: [String: Data?], _ message: String, _ key: VaultKey, in folder: URL,
                signer: SoftwareCommitSigner) async throws -> VaultPushResult {
        try await open(key, in: folder).commit(changes, message: message, branch: "current", signer: signer,
                                                writeKey: try XCTUnwrap(key.writeKey), accessToken: nil,
                                                writer: FolderVaultTransport(root: folder))
    }

    func objectCount(_ folder: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "bare/data").path)) ?? []).count
    }

    func testPushCreatesTheVaultThenOnlySendsWhatIsNew() async throws {
        let signer = SoftwareCommitSigner()
        let (created, device) = try await localVault(signer: signer)
        let key = created.key
        let server = try folder("server")
        let remote = FolderVaultTransport(root: server)
        let local = FolderVaultTransport(root: device)

        // First push: the server did not hold the vault.
        let first = try await VaultSync.transfer(key: key, from: local, to: remote, accessToken: nil)
        XCTAssertEqual(first.outcome, .created)
        XCTAssertEqual(first.commits, 2)
        XCTAssertEqual(first.objects, objectCount(device) + 1)          // every object, and the signer's public key
        let localHead = try await head(key, in: device)
        XCTAssertEqual(first.head, localHead)

        let reader = open(key, in: server)
        let pushedHead = try await reader.pull()
        XCTAssertEqual(pushedHead.commitId, localHead)
        XCTAssertTrue(pushedHead.signature.isVerified, "\(pushedHead.signature)")
        let readme = try await reader.readText("README.md")
        XCTAssertEqual(readme, "# Made on a device\n")

        // Nothing new: nothing sent.
        let again = try await VaultSync.transfer(key: key, from: local, to: remote, accessToken: nil)
        XCTAssertEqual(again.outcome, .upToDate)
        XCTAssertEqual(again.objects, 0)

        // Two more commits on the device, one changing a file and one adding a folder.
        try await commit(["README.md": Data("# Changed\n".utf8)], "Second note", key, in: device, signer: signer)
        try await commit(["debriefs/2026/11/13/a/debrief.md": Data("## Key points\n- one\n".utf8),
                          "debriefs/2026/11/13/a/audio.m4a": Data((0..<4_000).map { UInt8($0 % 251) })],
                         "Third note", key, in: device, signer: signer)
        let before = objectCount(server)
        let second = try await VaultSync.transfer(key: key, from: local, to: remote, accessToken: nil)
        XCTAssertEqual(second.outcome, .fastForwarded)
        XCTAssertEqual(second.commits, 2)
        XCTAssertEqual(second.objects, objectCount(server) - before)    // only what the server lacked
        XCTAssertEqual(objectCount(server), objectCount(device))

        let after = open(key, in: server)
        let history = try await after.history(limit: 10)
        XCTAssertEqual(history.map(\.message), ["Third note", "Second note", "First note", "Vault created"])
        XCTAssertTrue(history.allSatisfy { $0.signature.isVerified })
        let paths = try await after.files().map(\.path).sorted()
        XCTAssertEqual(paths, ["README.md", "debriefs/2026/11/13/a/audio.m4a", "debriefs/2026/11/13/a/debrief.md"])

        try await export(created: created, server: server, reader: after, name: "pushed")
    }

    func testPullCopiesAVaultThenMovesItForward() async throws {
        let signer = SoftwareCommitSigner()
        let (created, server) = try await localVault(signer: signer)       // plays the server here
        let key = created.key
        let device = try folder("second-device")
        let remote = FolderVaultTransport(root: server)
        let local = FolderVaultTransport(root: device)

        let first = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
        XCTAssertEqual(first.outcome, .created)
        let copied = try await open(key, in: device).readText("README.md")
        XCTAssertEqual(copied, "# Made on a device\n")

        // A read key is enough to pull.
        let readOnly = try VaultKey.parse(key.exportReadKey())
        XCTAssertNil(readOnly.writeKey)
        let third = try folder("read-only-device")
        let withReadKey = try await VaultSync.transfer(key: readOnly, from: remote, to: FolderVaultTransport(root: third), accessToken: nil)
        XCTAssertEqual(withReadKey.outcome, .created)

        try await commit(["more.md": Data("more\n".utf8)], "On the server", key, in: server, signer: signer)
        let second = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
        XCTAssertEqual(second.outcome, .fastForwarded)
        XCTAssertEqual(second.commits, 1)
        let deviceHead = try await head(key, in: device)
        let serverHead = try await head(key, in: server)
        XCTAssertEqual(deviceHead, serverHead)

        // The device is now level; a commit there makes the server the one behind.
        try await commit(["here.md": Data("here\n".utf8)], "On the device", key, in: device, signer: signer)
        let behind = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
        XCTAssertEqual(behind.outcome, .sourceBehind)
        XCTAssertEqual(behind.objects, 0)
        let stillAhead = try await head(key, in: device)
        XCTAssertNotEqual(stillAhead, serverHead)
    }

    func testWhenBothSidesChangedNothingMoves() async throws {
        let signer = SoftwareCommitSigner()
        let (created, device) = try await localVault(signer: signer)
        let key = created.key
        let server = try folder("server")
        let remote = FolderVaultTransport(root: server)
        let local = FolderVaultTransport(root: device)
        _ = try await VaultSync.transfer(key: key, from: local, to: remote, accessToken: nil)

        try await commit(["device.md": Data("device\n".utf8)], "On the device", key, in: device, signer: signer)
        try await commit(["server.md": Data("server\n".utf8)], "On the server", key, in: server, signer: SoftwareCommitSigner())
        let deviceHead = try await head(key, in: device)
        let serverHead = try await head(key, in: server)
        let serverObjects = objectCount(server)
        let deviceObjects = objectCount(device)

        let push = try await VaultSync.transfer(key: key, from: local, to: remote, accessToken: nil)
        XCTAssertEqual(push.outcome, .diverged)
        XCTAssertEqual(push.head, serverHead)
        let pull = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
        XCTAssertEqual(pull.outcome, .diverged)
        XCTAssertEqual(pull.head, deviceHead)

        // Neither ref moved and nothing was copied either way.
        let serverNow = try await head(key, in: server)
        let deviceNow = try await head(key, in: device)
        XCTAssertEqual(serverNow, serverHead)
        XCTAssertEqual(deviceNow, deviceHead)
        XCTAssertEqual(objectCount(server), serverObjects)
        XCTAssertEqual(objectCount(device), deviceObjects)
    }

    func testAVaultThatIsNotThereCannotBeSent() async throws {
        let key = try VaultKey.parse(VaultCreate.newKeyText())
        let empty = try folder("empty")
        let server = try folder("server")
        do {
            _ = try await VaultSync.transfer(key: key, from: FolderVaultTransport(root: empty),
                                             to: FolderVaultTransport(root: server), accessToken: nil)
            XCTFail("an absent vault was sent")
        } catch let error as VaultError {
            XCTAssertEqual(error, .vaultNotFoundOrWrongKey(vaultId: key.vaultId))
        }
        XCTAssertEqual(objectCount(server), 0)
    }

    func testAnObjectChangedOnTheServerIsRefusedAndNothingMoves() async throws {
        let signer = SoftwareCommitSigner()
        let (created, server) = try await localVault(signer: signer)
        let key = created.key
        let device = try folder("device")
        let remote = FolderVaultTransport(root: server)
        let local = FolderVaultTransport(root: device)
        _ = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
        let before = try await head(key, in: device)

        let result = try await commit(["new.md": Data("new\n".utf8)], "Tampered with", key, in: server, signer: signer)
        try flipByte(at: server.appending(path: "bare/data/\(result.commit.commitId)"), offset: 20)
        do {
            _ = try await VaultSync.transfer(key: key, from: remote, to: local, accessToken: nil)
            XCTFail("a changed object was accepted")
        } catch let error as VaultError {
            guard case .integrity = error else { return XCTFail("\(error)") }
        }
        let after = try await head(key, in: device)
        XCTAssertEqual(after, before)
    }

    func testNamesThatBecomePathsMustBePlain() {
        XCTAssertTrue(VaultSync.isSafeName("ref-pid-muw-0123456789ab"))
        XCTAssertTrue(VaultSync.isSafeName("key-rnd-imm-0123456789abcdef"))
        XCTAssertFalse(VaultSync.isSafeName("../refs/x"))
        XCTAssertFalse(VaultSync.isSafeName("a/b"))
        XCTAssertFalse(VaultSync.isSafeName(""))
        XCTAssertFalse(VaultSync.isSafeName("a.b"))
    }

    func testBatchesKeepToACountAndASize() {
        func op(_ bytes: Int) -> VaultBatchOperation {
            VaultBatchOperation(op: .write, fileId: "bare/data/x", data: Data(count: bytes))
        }
        XCTAssertTrue(VaultBatchOperation.batches([]).isEmpty)
        let small = VaultBatchOperation.batches(Array(repeating: op(10), count: 120))
        XCTAssertEqual(small.map(\.count), [50, 50, 20])
        // A large object travels alone; small ones around it are grouped up to the size.
        let mixed = VaultBatchOperation.batches([op(1_000_000), op(3_800_000), op(1_000_000), op(1_900_000), op(200_000)])
        XCTAssertEqual(mixed.map(\.count), [1, 1, 2, 1])
        XCTAssertTrue(mixed.allSatisfy { $0.count == 1 || $0.reduce(0) { $0 + $1.data.count } <= VaultBatchOperation.batchBytes })
    }

    /// The vault as the server holds it after the push, and what sgit should find, for the Linux read-back job.
    func export(created: VaultCreated, server: URL, reader: SGitVault, name: String) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: server, to: dest.appending(path: "server"))
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
