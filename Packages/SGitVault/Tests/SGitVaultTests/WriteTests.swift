import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// The Swift writer against the throwaway fixtures. The vault it writes is exported (when
/// SGITVAULT_ROUNDTRIP_OUT is set) so CI can have sgit itself read it on Linux.
@MainActor
final class WriteTests: XCTestCase {

    func writeKey(_ fixture: Fixture) -> SymmetricKey { SymmetricKey(data: Data(hexString: fixture.expected.write_key_hex)!) }

    /// Rebuilding a commit's tree from its own files must give sgit's tree id, byte for byte.
    func testUnchangedTreeHasSgitsTreeId() async throws {
        for fixture in Fixture.all {
            for branch in fixture.expected.branches.keys {
                let vault = openVault(fixture, branch: branch)
                let head = try await vault.pull()
                let files = try await vault.files()
                let format = await vault.format
                let builder = VaultCommitBuilder(readKey: fixture.readKey, idWidth: format?.objectIdWidth ?? 12,
                                                 deflateBlobs: format?.features.contains("blob-deflate") ?? false)
                let out = try builder.build(base: files, changes: [:], parents: [head.commitId], message: "noop",
                                            branchId: VaultCommitBuilder.newBranchId(), signer: SoftwareCommitSigner())
                XCTAssertEqual(out.treeId, head.treeId, "\(fixture.name)/\(branch)")
            }
        }
    }

    func testPythonJSONMatchesPythonDumps() {
        // Python: json.dumps({"a": "Olá\n", "b": [None, True, 3], "c": {"d": ""}})
        let value = PythonJSON.object([("a", .string("Olá\n")), ("b", .array([.null, .bool(true), .int(3)])),
                                       ("c", .object([("d", .string(""))]))])
        XCTAssertEqual(value.dumps(), #"{"a": "Ol\u00e1\n", "b": [null, true, 3], "c": {"d": ""}}"#)
    }

    func testCommitToANewDeviceBranchAndReadItBack() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let transport = FolderVaultTransport(root: server)
        let signer = SoftwareCommitSigner()
        let vault = openVault(fixture, server: server)
        let currentHead = try await vault.pull()

        let changes: [String: Data?] = [
            "device/iphone.md": Data("# Written by SGitVault in Swift\n".utf8),
            "picks.json": Data(#"{"v":1,"picks":[{"id":"events/demo","at":1762650000000},{"id":"events/swift","at":1762660000000}]}"#.utf8),
            "docs/deep/note.txt": nil,
        ]
        let result = try await vault.commit(changes, message: "Swift commit on device-iphone", branch: "device-iphone",
                                            signer: signer, writeKey: writeKey(fixture), accessToken: nil,
                                            writer: transport)
        XCTAssertTrue(result.createdBranch)
        XCTAssertTrue(result.commit.signature.isVerified, "\(result.commit.signature)")
        XCTAssertEqual(result.commit.parents, [currentHead.commitId])

        // A fresh reader (empty cache) sees the new branch.
        let reader = openVault(fixture, branch: "device-iphone", server: server)
        let paths = try await reader.files().map(\.path)
        XCTAssertTrue(paths.contains("device/iphone.md"))
        XCTAssertFalse(paths.contains("docs/deep/note.txt"))
        let iphone = try await reader.readText("device/iphone.md")
        XCTAssertEqual(iphone, "# Written by SGitVault in Swift\n")
        let readme = try await reader.readText("README.md")
        XCTAssertEqual(readme, fixture.expected.branches["current"]!.files["README.md"]!.text)
        let history = try await reader.history(limit: 10)
        XCTAssertEqual(history.map(\.message),
                       ["Swift commit on device-iphone"] + fixture.expected.branches["current"]!.messages)
        XCTAssertTrue(history.allSatisfy { $0.signature.isVerified })
        let branches = await reader.branches
        XCTAssertEqual(branches.filter { $0.type == .named }.count, 3)

        // "current" did not move.
        let current = openVault(fixture, server: server)
        let stillCurrent = try await current.pull()
        XCTAssertEqual(stillCurrent.commitId, currentHead.commitId)

        // A second commit moves the existing branch (compare-and-swap on its ref).
        let second = try await vault.commit(["device/iphone.md": Data("second\n".utf8)], message: "Second Swift commit",
                                            branch: "device-iphone", signer: signer, writeKey: writeKey(fixture),
                                            accessToken: nil, writer: transport)
        XCTAssertFalse(second.createdBranch)
        XCTAssertEqual(second.commit.parents, [result.commit.commitId])

        try await exportForSgit(fixture: fixture, server: server, branch: "device-iphone", reader: reader)
    }

    func testDeflateVaultWriteRoundTrip() async throws {
        let fixture = Fixture.deflate
        let server = try fixture.copyOfServer()
        let vault = openVault(fixture, server: server)
        let big = String(repeating: "Swift writes a compressible line.\n", count: 300)
        let result = try await vault.commit(["swift/big.txt": Data(big.utf8)], message: "Swift deflate commit",
                                            branch: "device-ipad", signer: SoftwareCommitSigner(),
                                            writeKey: writeKey(fixture), accessToken: nil,
                                            writer: FolderVaultTransport(root: server))
        XCTAssertFalse(result.createdBranch)
        XCTAssertEqual(VaultCrypto.objectIdWidth(result.commit.commitId), 32)
        let reader = openVault(fixture, branch: "device-ipad", server: server)
        let readBack = try await reader.readText("swift/big.txt")
        XCTAssertEqual(readBack, big)
        let readerFiles = try await reader.files()
        let blob = try XCTUnwrap(readerFiles.first { $0.path == "swift/big.txt" })
        let raw = try Data(contentsOf: server.appending(path: "bare/data/\(blob.blobId)"))
        XCTAssertEqual(raw.prefix(5), VaultCrypto.deflateMagic)
        try await exportForSgit(fixture: fixture, server: server, branch: "device-ipad", reader: reader)
    }

    func testLostRaceIsAConflictAndOverwritesNothing() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let racing = RacingWriter(inner: FolderVaultTransport(root: server), root: server)
        let vault = openVault(fixture, server: server)
        do {
            _ = try await vault.commit(["x.txt": Data("x".utf8)], message: "loses the race", branch: "current",
                                       signer: SoftwareCommitSigner(), writeKey: writeKey(fixture),
                                       accessToken: nil, writer: racing)
            XCTFail("expected a push conflict")
        } catch VaultError.pushConflict(let branch) {
            XCTAssertEqual(branch, "current")
        }
        // The ref holds the other writer's bytes, not ours.
        let refs = try FileManager.default.contentsOfDirectory(atPath: server.appending(path: "bare/refs").path)
        XCTAssertTrue(try refs.contains { try Data(contentsOf: server.appending(path: "bare/refs/\($0)")) == RacingWriter.otherBytes })
    }

    func testCommitMessageLimitAndBadPaths() throws {
        let builder = VaultCommitBuilder(readKey: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try builder.build(base: [], changes: [:], parents: [], message: String(repeating: "x", count: 741),
                                               branchId: "branch-named-00000000", signer: SoftwareCommitSigner()))
        for bad in ["", "/abs", "a/../b", "a//b", "./a"] {
            XCTAssertThrowsError(try builder.build(base: [], changes: [bad: Data()], parents: [], message: "m",
                                                   branchId: "branch-named-00000000", signer: SoftwareCommitSigner()), bad)
        }
    }

    // MARK: Export for sgit

    /// Write the vault (as the server holds it) and what sgit should find, for the Linux read-back job.
    func exportForSgit(fixture: Fixture, server: URL, branch: String, reader _: SGitVault) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: fixture.name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: server, to: dest.appending(path: "server"))
        // A fresh reader: `reader` may have pulled before the test's later commits.
        let reader = openVault(fixture, branch: branch, server: server)
        var files: [String: [String: Any]] = [:]
        for file in try await reader.files() {
            let data = try await reader.read(file.path)
            files[file.path] = ["size": data.count, "sha256": sha256Hex(data)]
        }
        let messages = try await reader.history(limit: 20).map(\.message)
        let expected: [String: Any] = [
            "WARNING": "THROWAWAY test keys for test fixtures only.",
            "vault_key": fixture.expected.vault_key, "vault_id": fixture.expected.vault_id,
            "branch": branch, "files": files, "messages": messages,
        ]
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
            .write(to: dest.appending(path: "expected.json"))
    }
}

/// A writer that loses every compare-and-swap: just before applying a batch, another writer changes the file.
struct RacingWriter: VaultWriteTransport {
    static let otherBytes = Data("someone else's ref".utf8)
    let inner: FolderVaultTransport
    let root: URL

    func batch(vaultId: String, writeKey: String, accessToken: String?,
               operations: [VaultBatchOperation]) async throws -> VaultBatchResult {
        for op in operations where op.op == .writeIfMatch {
            try Self.otherBytes.write(to: root.appending(path: op.fileId))
        }
        return try await inner.batch(vaultId: vaultId, writeKey: writeKey, accessToken: accessToken, operations: operations)
    }
}
