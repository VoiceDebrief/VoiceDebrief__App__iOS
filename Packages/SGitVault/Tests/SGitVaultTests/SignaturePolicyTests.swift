import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// S1: signatures are enforced and signer keys are pinned. Negative controls first.
@MainActor
final class SignaturePolicyTests: XCTestCase {

    func writeKey(_ fixture: Fixture) -> SymmetricKey { SymmetricKey(data: Data(hexString: fixture.expected.write_key_hex)!) }

    /// The keys that signed the fixture's history, as trust-on-first-use pins them.
    func fixtureSigners(_ fixture: Fixture) async throws -> Set<String> {
        let vault = openVault(fixture, requireSignatures: true, trust: VaultTrust())
        try await vault.pull()
        let trust = await vault.trust
        return try XCTUnwrap(trust).pinnedKeyIds
    }

    /// Commit on `current` with a reader that does not enforce anything (the writer under test).
    func push(_ fixture: Fixture, server: URL, _ changes: [String: Data?], signer: any VaultCommitSigner) async throws {
        let writer = openVault(fixture, server: server)
        _ = try await writer.commit(changes, message: "test commit", branch: "current", signer: signer,
                                    writeKey: writeKey(fixture), accessToken: nil,
                                    writer: FolderVaultTransport(root: server))
    }

    func strictReader(_ fixture: Fixture, server: URL, pins: Set<String>, firstUse: Bool = true) -> SGitVault {
        openVault(fixture, server: server, requireSignatures: true,
                  trust: VaultTrust(pinnedKeyIds: pins, trustOnFirstUse: firstUse))
    }

    // MARK: sgit's own vaults still read

    func testSgitFixturesReadStrictlyAndPinTheirSigners() async throws {
        for fixture in Fixture.all {
            for branch in fixture.expected.branches.keys {
                let vault = openVault(fixture, branch: branch, requireSignatures: true, trust: VaultTrust())
                let head = try await vault.pull()
                XCTAssertTrue(head.signature.isVerified)
                let trust = await vault.trust
                let pins = try XCTUnwrap(trust).pinnedKeyIds
                XCTAssertFalse(pins.isEmpty)
                let history = try await vault.history(limit: 50)
                XCTAssertEqual(pins, Set(history.compactMap(\.authorKeyId)), "\(fixture.name)/\(branch)")
                // Reading again with those pins: accepted without first use.
                let again = openVault(fixture, branch: branch, requireSignatures: true,
                                      trust: VaultTrust(pinnedKeyIds: pins, trustOnFirstUse: false))
                try await again.pull()
            }
        }
    }

    // MARK: Good, unknown, tampered

    func testGoodSignatureFromAPinnedKeyIsAccepted() async throws {
        let fixture = Fixture.plain
        let pins = try await fixtureSigners(fixture)
        let server = try fixture.copyOfServer()
        let device = SoftwareCommitSigner()
        try await push(fixture, server: server, ["device.md": Data("hi\n".utf8)], signer: device)
        let reader = strictReader(fixture, server: server, pins: pins.union([device.keyId]))
        let head = try await reader.pull()
        XCTAssertEqual(head.signature, .verified(keyId: device.keyId))
    }

    func testUnknownSignerIsRefusedEvenThoughItsKeyIsInTheVault() async throws {
        let fixture = Fixture.plain
        let pins = try await fixtureSigners(fixture)
        let server = try fixture.copyOfServer()
        let stranger = SoftwareCommitSigner()
        try await push(fixture, server: server, ["forged.json": Data("{}".utf8)], signer: stranger)
        // The stranger's public key is in bare/keys/ and its signature verifies; that is not enough.
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.appending(path: "bare/keys/\(stranger.keyId)").path))
        let reader = strictReader(fixture, server: server, pins: pins)
        do {
            try await reader.pull()
            XCTFail("an unpinned signer must be refused")
        } catch VaultError.untrustedSigner(_, let keyId) {
            XCTAssertEqual(keyId, stranger.keyId)
        }
        // Control: the permissive reader still reads it (that is the old behaviour, now opt-in).
        let permissive = openVault(fixture, server: server)
        _ = try await permissive.pull()
        // Pinning the key on purpose (the user trusts it) makes it acceptable.
        await reader.pin(stranger.keyId)
        try await reader.pull()
    }

    func testTamperedSignatureIsAlwaysRefused() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        do {
            try await push(fixture, server: server, ["x.txt": Data("x".utf8)], signer: BrokenSigner())
            XCTFail("the read-back of a commit with a broken signature must fail")
        } catch VaultError.signatureInvalid {
            // expected: refused even by a reader that does not require signatures
        }
        for strict in [false, true] {
            let reader = openVault(fixture, server: server, requireSignatures: strict, trust: strict ? VaultTrust() : nil)
            do {
                try await reader.pull()
                XCTFail("invalid signature accepted (strict: \(strict))")
            } catch VaultError.signatureInvalid {}
        }
    }

    func testNoPinsAndNoFirstUseRefuses() async throws {
        let reader = openVault(.plain, requireSignatures: true, trust: VaultTrust(pinnedKeyIds: [], trustOnFirstUse: false))
        do {
            try await reader.pull()
            XCTFail("expected untrustedSigner")
        } catch VaultError.untrustedSigner {}
    }

    // MARK: The trust file

    func testTrustFileFromAPinnedKeyAddsKeysOneLevelOnly() async throws {
        let fixture = Fixture.plain
        let pins = try await fixtureSigners(fixture)
        let server = try fixture.copyOfServer()
        let device = SoftwareCommitSigner()          // pinned (this device)
        let teammate = SoftwareCommitSigner()        // listed by the device
        let third = SoftwareCommitSigner()           // listed only by the teammate
        let trusted = pins.union([device.keyId])

        try await push(fixture, server: server,
                       [VaultTrust.trustFile: VaultTrust.document(listing: [teammate.keyId])], signer: device)
        try await push(fixture, server: server, ["notes/teammate.md": Data("from a teammate\n".utf8)], signer: teammate)
        let head = try await strictReader(fixture, server: server, pins: trusted).pull()
        XCTAssertEqual(head.signature, .verified(keyId: teammate.keyId))

        // The teammate lists a third key; that listing does not count (the teammate is not pinned).
        try await push(fixture, server: server,
                       [VaultTrust.trustFile: VaultTrust.document(listing: [teammate.keyId, third.keyId])], signer: teammate)
        try await push(fixture, server: server, ["notes/third.md": Data("from a third key\n".utf8)], signer: third)
        do {
            try await strictReader(fixture, server: server, pins: trusted).pull()
            XCTFail("a key listed by an unpinned key must be refused")
        } catch VaultError.untrustedSigner(_, let keyId) {
            XCTAssertEqual(keyId, third.keyId)
        }
    }

    func testTrustFileParsing() {
        XCTAssertEqual(VaultTrust.listedKeys(in: VaultTrust.document(listing: ["key-rnd-imm-00aa", "key-rnd-imm-11bb"])),
                       ["key-rnd-imm-00aa", "key-rnd-imm-11bb"])
        XCTAssertEqual(VaultTrust.listedKeys(in: Data("not json".utf8)), [])
        XCTAssertEqual(VaultTrust.listedKeys(in: Data(#"{"v":1,"keys":["evil","key-rnd-imm-ok"]}"#.utf8)), ["key-rnd-imm-ok"])
    }

    // MARK: S7 guards

    func testFoldersNestedTooDeepAreRefused() async throws {
        let fixture = Fixture.plain
        let server = try fixture.copyOfServer()
        let deep = Array(repeating: "d", count: SGitVault.maxTreeDepth + 2).joined(separator: "/") + "/f.txt"
        let device = SoftwareCommitSigner()
        do {
            try await push(fixture, server: server, [deep: Data("deep".utf8)], signer: device)
            XCTFail("the read-back of a too-deep tree must fail")
        } catch VaultError.malformed(_, let detail) {
            XCTAssertTrue(detail.contains("deeper"), detail)
        }
        // Control: a deep but allowed path reads.
        let server2 = try fixture.copyOfServer()
        let ok = Array(repeating: "d", count: 20).joined(separator: "/") + "/f.txt"
        try await push(fixture, server: server2, [ok: Data("fine".utf8)], signer: device)
        let reader = openVault(fixture, server: server2)
        let text = try await reader.readText(ok)
        XCTAssertEqual(text, "fine")
    }

    func testInflateStopsAtTheCap() throws {
        let zeros = Data(count: 1_000_000)
        let packed = try XCTUnwrap(Zlib.compress(zeros))
        XCTAssertLessThan(packed.count, 10_000)
        XCTAssertNil(Zlib.decompress(packed, limit: 100_000), "a deflate bomb must stop at the cap")
        XCTAssertEqual(Zlib.decompress(packed, limit: 2_000_000), zeros)
        XCTAssertNil(Zlib.decompress(Data(packed.prefix(packed.count / 2))), "a truncated stream is refused")
    }

    func testEmptyPassphraseDoesNotCrash() {
        // Python: hashlib.pbkdf2_hmac('sha256', b'', b'x', 1)
        let key = VaultCrypto.pbkdf2(passphrase: "", salt: "x", rounds: 1)
        XCTAssertEqual(key.withUnsafeBytes { Data($0).hexString },
                       "c9bf622ae9ea3628d7450294bcee8ba328b05607ceccab35fb781a5b2f2bcf17")
    }

    func testUserFacingErrorsCarryNoIdsOrPaths() {
        let errors: [VaultError] = [
            .untrustedSigner(commitId: "obj-cas-imm-0123456789ab", keyId: "key-rnd-imm-0011223344556677"),
            .signatureInvalid(commitId: "obj-cas-imm-0123456789ab"),
            .integrity(objectId: "obj-cas-imm-0123456789ab", actual: "obj-cas-imm-ba9876543210"),
            .decryptFailed(path: "bare/data/obj-cas-imm-0123456789ab"),
            .tooLarge(path: "bare/data/obj-cas-imm-0123456789ab", bytes: 99_000_000),
            .vaultNotFoundOrWrongKey(vaultId: "fixtplain1"),
        ]
        for error in errors {
            let text = error.localizedDescription
            XCTAssertFalse(text.contains("obj-cas-imm") || text.contains("key-rnd-imm") || text.contains("bare/"), text)
            XCTAssertFalse(text.contains("Error Domain"), text)
            XCTAssertTrue(error.description.contains("imm") || error.description.contains("fixtplain1"),
                          "the detail stays in description")
        }
    }
}

/// Signs with 64 random bytes: the commit hashes correctly, but its signature does not verify.
struct BrokenSigner: VaultCommitSigner {
    let keyId = VaultCommitBuilder.newKeyId()
    let publicKeyPEM = P256.Signing.PrivateKey().publicKey.pemRepresentation
    func sign(_ data: Data) throws -> Data { Data((0..<64).map { _ in UInt8.random(in: 0...255) }) }
}
