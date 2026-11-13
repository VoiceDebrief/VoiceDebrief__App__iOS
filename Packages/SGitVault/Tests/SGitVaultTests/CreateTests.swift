import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// Creating a vault in Swift, then reading and writing it with the same reader the fixtures use.
/// The vault is exported (when SGITVAULT_ROUNDTRIP_OUT is set) so CI can have sgit itself clone it.
@MainActor
final class CreateTests: XCTestCase {
    func temporaryServer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sgitvault-created-\(UUID().uuidString)",
                                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func open(_ key: VaultKey, server: URL) -> SGitVault {
        SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: temporaryCache(),
                  log: VaultTrafficLog(), transport: FolderVaultTransport(root: server), branch: "current")
    }

    func testANewKeyHasSgitsShape() throws {
        let text = VaultCreate.newKeyText()
        XCTAssertEqual(VaultKey.classify(text), .vault)
        let body = text.dropFirst("sgit_private_vault_".count)
        let parts = body.split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].count, 24)
        XCTAssertEqual(parts[1].count, 8)
        XCTAssertTrue(body.allSatisfy { $0 == ":" || $0.isNumber || ($0.isLowercase && $0.isASCII) })
        XCTAssertNotEqual(VaultCreate.newKeyText(), text)
        XCTAssertEqual(VaultCreate.randomText(0), "")
    }

    func testTheIndexIsInSgitsMemberOrder() {
        let json = VaultCreate.indexJSON(branchId: "branch-named-00", refId: "ref-pid-muw-00", keyId: "key-rnd-imm-00",
                                         timestampMs: 1).dumps()
        XCTAssertEqual(json, #"{"schema": "branch_index_v1", "format": null, "min_client": null, "branches": [{"branch_id": "branch-named-00", "name": "current", "branch_type": "named", "head_ref_id": "ref-pid-muw-00", "public_key_id": "key-rnd-imm-00", "private_key_id": null, "created_at": 1, "creator_branch": null, "display_name": null}], "features": [], "tags": []}"#)
    }

    func testCreateThenReadThenCommit() async throws {
        let server = try temporaryServer()
        let transport = FolderVaultTransport(root: server)
        let signer = SoftwareCommitSigner()
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: transport)
        XCTAssertTrue(created.key.canWrite)

        // A new vault is one signed commit over an empty tree.
        let vault = open(created.key, server: server)
        let head = try await vault.pull()
        XCTAssertEqual(head.commitId, created.commitId)
        XCTAssertEqual(head.parents, [])
        XCTAssertEqual(head.message, "Vault created")
        XCTAssertTrue(head.signature.isVerified, "\(head.signature)")
        let empty = try await vault.files()
        XCTAssertTrue(empty.isEmpty)

        // It takes a commit like any other vault.
        let writeKey = try XCTUnwrap(created.key.writeKey)
        let result = try await vault.commit(["README.md": Data("# Made in Swift\n".utf8),
                                             "debriefs/2026/11/13/a/debrief.md": Data("## Key points\n- one\n".utf8)],
                                            message: "First files", branch: "current", signer: signer,
                                            writeKey: writeKey, accessToken: nil, writer: transport)
        XCTAssertFalse(result.createdBranch)
        XCTAssertEqual(result.commit.parents, [created.commitId])

        let reader = open(created.key, server: server)
        let paths = try await reader.files().map(\.path).sorted()
        XCTAssertEqual(paths, ["README.md", "debriefs/2026/11/13/a/debrief.md"])
        let readme = try await reader.readText("README.md")
        XCTAssertEqual(readme, "# Made in Swift\n")
        let history = try await reader.history(limit: 10)
        XCTAssertEqual(history.map(\.message), ["First files", "Vault created"])
        XCTAssertTrue(history.allSatisfy { $0.signature.isVerified })

        try await export(created: created, server: server, reader: reader)
    }

    func testCreatingAtAGivenKeyUsesThatKey() async throws {
        let server = try temporaryServer()
        let text = VaultCreate.newKeyText()
        let created = try await VaultCreate.create(keyText: text, signer: SoftwareCommitSigner(), accessToken: nil,
                                                   writer: FolderVaultTransport(root: server))
        XCTAssertEqual(created.keyText, text)
        XCTAssertEqual(created.key.vaultId, String(text.split(separator: ":")[1]))
    }

    func testAReadKeyCannotCreate() async throws {
        let server = try temporaryServer()
        let key = try VaultKey.parse(VaultCreate.newKeyText())
        do {
            _ = try await VaultCreate.create(keyText: key.exportReadKey(), signer: SoftwareCommitSigner(), accessToken: nil,
                                             writer: FolderVaultTransport(root: server))
            XCTFail("a read key created a vault")
        } catch {
            // expected
        }
    }

    /// The vault as the server holds it, and what sgit should find, for the Linux read-back job.
    func export(created: VaultCreated, server: URL, reader: SGitVault) async throws {
        guard let out = ProcessInfo.processInfo.environment["SGITVAULT_ROUNDTRIP_OUT"], !out.isEmpty else { return }
        let dest = URL(fileURLWithPath: out).appending(path: "created", directoryHint: .isDirectory)
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
