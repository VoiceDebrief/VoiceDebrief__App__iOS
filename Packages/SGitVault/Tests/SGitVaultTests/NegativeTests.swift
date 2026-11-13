import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// Negative controls: every check must fail when its input is wrong.
@MainActor
final class NegativeTests: XCTestCase {

    func testWrongKeyIsACleanError() async throws {
        for key in [SymmetricKey(size: .bits256), Fixture.deflate.readKey] {
            let vault = openVault(.plain, readKey: key)
            do {
                try await vault.pull()
                XCTFail("a wrong key must not open the vault")
            } catch VaultError.vaultNotFoundOrWrongKey(let id) {
                XCTAssertEqual(id, "fixtplain1")
            }
        }
    }

    func testFlippedByteInABlobFailsVerification() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let vault = openVault(fixture, server: server)
        let readmeFiles = try await vault.files()
        let readme = try XCTUnwrap(readmeFiles.first { $0.path == "README.md" })
        try flipByte(at: server.appending(path: "bare/data/\(readme.blobId)"), offset: 20)
        do {
            _ = try await vault.read("README.md")
            XCTFail("a changed blob must fail its hash check")
        } catch VaultError.integrity(let id, let actual) {
            XCTAssertEqual(id, readme.blobId)
            XCTAssertNotEqual(actual, readme.blobId)
        }
        // Control: an untouched file still reads.
        let picks = try await vault.readText("picks.json")
        XCTAssertTrue(picks.contains("events/demo"))
    }

    func testFlippedByteInACommitFailsThePull() async throws {
        let fixture = Fixture.deflate
        let server = try fixture.copyOfServer()
        let clean = openVault(fixture, server: server)
        let head = try await clean.pull()
        try flipByte(at: server.appending(path: "bare/data/\(head.commitId)"), offset: 30)
        let vault = openVault(fixture, server: server)        // fresh cache
        do {
            try await vault.pull()
            XCTFail("a changed commit must fail its hash check")
        } catch VaultError.integrity(let id, _) {
            XCTAssertEqual(id, head.commitId)
        }
    }

    func testRehashedTamperedObjectStillFailsDecryption() async throws {
        // An attacker who renames a changed object to its new hash passes the id check,
        // but AES-GCM's tag still refuses it.
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let clean = openVault(fixture, server: server)
        let readmeFiles = try await clean.files()
        let readme = try XCTUnwrap(readmeFiles.first { $0.path == "README.md" })
        let url = server.appending(path: "bare/data/\(readme.blobId)")
        var data = try Data(contentsOf: url)
        data[20] ^= 0x01
        let forgedId = VaultCrypto.objectId(of: data, width: 12)
        let vault = openVault(fixture, server: server)
        let forged = VaultFile(path: "README.md", size: readme.size, blobId: forgedId,
                               contentHash: readme.contentHash, contentType: nil, large: false)
        try data.write(to: server.appending(path: "bare/data/\(forged.blobId)"))
        XCTAssertTrue(VaultCrypto.objectIdMatches(forgedId, ciphertext: data))
        XCTAssertThrowsError(try VaultCrypto.open(data, readKey: fixture.readKey,
                                                  structureKey: VaultCrypto.structureKey(readKey: fixture.readKey)))
        _ = vault
    }

    func testTamperedRefFailsDecryption() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let refs = try FileManager.default.contentsOfDirectory(
            at: server.appending(path: "bare/refs"), includingPropertiesForKeys: nil)
        for ref in refs { try flipByte(at: ref, offset: 15) }
        let vault = openVault(fixture, server: server)
        do {
            try await vault.pull()
            XCTFail("a changed ref must not decrypt")
        } catch VaultError.decryptFailed(let path) {
            XCTAssertTrue(path.hasPrefix("bare/refs/"), path)
        }
    }

    func testDamagedCacheFileIsReplaced() async throws {
        let cache = temporaryCache()
        let first = openVault(.plain, cache: cache)
        let readmeFiles = try await first.files()
        let readme = try XCTUnwrap(readmeFiles.first { $0.path == "README.md" })
        _ = try await first.read("README.md")
        try flipByte(at: cache.appending(path: "fixtplain1/\(readme.blobId)"), offset: 3)
        let log = VaultTrafficLog()
        let second = openVault(.plain, cache: cache, log: log)
        let text = try await second.readText("README.md")
        XCTAssertTrue(text.hasPrefix("# Fixture vault"))
        XCTAssertTrue(log.events.contains { $0.kind == .error && $0.detail.contains("cached copy") })
    }

    func testPackVaultIsRefused() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let index = """
        {"schema":"branch_index_v1","format":1,"min_client":"0.24.0","branches":[],"features":["packs","blob-deflate"]}
        """
        let sealed = try VaultCrypto.seal(Data(index.utf8), key: fixture.readKey)
        try sealed.write(to: server.appending(path: "bare/indexes/\(fixture.expected.branch_index_file_id)"))
        let vault = openVault(fixture, server: server)
        do {
            try await vault.pull()
            XCTFail("a pack vault must be refused")
        } catch VaultError.unsupportedFormat(let why) {
            XCTAssertTrue(why.contains("pack"), why)
        }
    }

    func testMissingFileIsAClearError() async throws {
        let vault = openVault(.plain)
        do {
            _ = try await vault.read("no/such/file.txt")
            XCTFail("expected fileNotFound")
        } catch VaultError.fileNotFound(let path) {
            XCTAssertEqual(path, "no/such/file.txt")
        }
    }

    func testSignatureCheckFailsOnChangedBytes() throws {
        // Negative control for signature verification: sign canonical bytes, change one field.
        let key = P256.Signing.PrivateKey()
        let commit = #"{"schema":"commit_v1","tree_id":"obj-cas-imm-0123456789ab","parents":[],"timestamp_ms":1}"#
        let bytes = try CanonicalJSON.signingBytes(commitJSON: Data(commit.utf8))
        let signature = try key.signature(for: bytes)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: bytes))
        let changed = try CanonicalJSON.signingBytes(commitJSON: Data(commit.replacingOccurrences(of: "\"timestamp_ms\":1", with: "\"timestamp_ms\":2").utf8))
        XCTAssertFalse(key.publicKey.isValidSignature(signature, for: changed))
    }
}
