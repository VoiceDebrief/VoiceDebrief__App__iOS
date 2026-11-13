import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

final class CryptoTests: XCTestCase {

    func testFileIdsMatchSgit() {
        for fixture in Fixture.all {
            XCTAssertEqual(VaultCrypto.branchIndexFileId(readKey: fixture.readKey, vaultId: fixture.expected.vault_id),
                           fixture.expected.branch_index_file_id, fixture.name)
            XCTAssertEqual(VaultCrypto.refFileId(readKey: fixture.readKey, vaultId: fixture.expected.vault_id),
                           fixture.expected.ref_file_id, fixture.name)
            // The index file exists on the "server" under that id.
            let path = fixture.server.appending(path: "bare/indexes/\(fixture.expected.branch_index_file_id)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), fixture.name)
        }
    }

    func testFileIdsDifferForADifferentKey() {
        let other = SymmetricKey(size: .bits256)
        XCTAssertNotEqual(VaultCrypto.branchIndexFileId(readKey: other, vaultId: Fixture.plain.expected.vault_id),
                          Fixture.plain.expected.branch_index_file_id)
    }

    func testVaultKeyDerivesSgitReadAndWriteKeys() throws {
        for fixture in Fixture.all {
            let key = try VaultKey.parse(fixture.expected.vault_key)
            XCTAssertEqual(key.kind, .vault)
            XCTAssertEqual(key.vaultId, fixture.expected.vault_id)
            XCTAssertEqual(key.readKey.withUnsafeBytes { Data($0).hexString }, fixture.expected.read_key_hex)
            XCTAssertEqual(key.writeKey?.withUnsafeBytes { Data($0).hexString }, fixture.expected.write_key_hex)
            XCTAssertTrue(key.canWrite)
        }
    }

    func testReadKeyForms() throws {
        let f = Fixture.plain.expected
        let privateKey = try VaultKey.parse(f.read_key)
        XCTAssertEqual(privateKey.kind, .privateRead)
        XCTAssertEqual(privateKey.vaultId, f.vault_id)
        XCTAssertFalse(privateKey.canWrite)
        XCTAssertEqual(privateKey.readKey.withUnsafeBytes { Data($0).hexString }, f.read_key_hex)

        let publicKey = try VaultKey.parse("sgit_public_read_\(f.read_key_hex):\(f.vault_id)")
        XCTAssertEqual(publicKey.kind, .publicRead)

        let bare = try VaultKey.parse("  \(f.read_key_hex):\(f.vault_id)\n")
        XCTAssertEqual(bare.kind, .bareRead)
        XCTAssertEqual(bare.readKey.withUnsafeBytes { Data($0).hexString }, f.read_key_hex)

        // A read key without a vault id takes the one given separately.
        let noId = try VaultKey.parse("sgit_private_read_\(f.read_key_hex)", vaultId: f.vault_id)
        XCTAssertEqual(noId.vaultId, f.vault_id)

        XCTAssertEqual(privateKey.exportReadKey(), f.read_key)
        XCTAssertFalse(privateKey.description.contains(f.read_key_hex), "description must not show the key")
    }

    func testInvalidKeysAreRefusedCleanly() {
        let bad = [
            "",
            "hello",
            "sgit_private_read_abcd:fixtplain1",                         // too short
            "sgit_private_read_\(String(repeating: "z", count: 64)):fixtplain1",   // not hex
            "sgit_private_read_\(String(repeating: "a", count: 64)):Bad-Id",       // vault id rule
            "sgit_private_read_\(String(repeating: "a", count: 64))",              // no vault id
            "sgit_private_vault_:fixtplain1",                             // no passphrase
        ]
        for text in bad {
            XCTAssertThrowsError(try VaultKey.parse(text), text) { error in
                guard let vaultError = error as? VaultError, case .invalidKey = vaultError else {
                    return XCTFail("\(text): \(error)")
                }
            }
        }
    }

    func testAESGCMRoundTripAndWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try VaultCrypto.seal(Data("hello".utf8), key: key)
        XCTAssertEqual(sealed.count, 12 + 5 + 16)
        XCTAssertEqual(try VaultCrypto.open(sealed, readKey: key, structureKey: nil).plaintext, Data("hello".utf8))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, readKey: SymmetricKey(size: .bits256), structureKey: nil))
    }

    func testDeterministicSealIsStable() throws {
        let key = SymmetricKey(size: .bits256)
        let a = try VaultCrypto.sealDeterministic(Data("tree".utf8), key: key)
        let b = try VaultCrypto.sealDeterministic(Data("tree".utf8), key: key)
        XCTAssertEqual(a, b)
    }

    func testObjectIdWidths() {
        let data = Data("ciphertext".utf8)
        let id12 = VaultCrypto.objectId(of: data, width: 12)
        let id32 = VaultCrypto.objectId(of: data, width: 32)
        XCTAssertEqual(VaultCrypto.objectIdWidth(id12), 12)
        XCTAssertEqual(VaultCrypto.objectIdWidth(id32), 32)
        XCTAssertTrue(VaultCrypto.objectIdMatches(id12, ciphertext: data))
        XCTAssertTrue(VaultCrypto.objectIdMatches(id32, ciphertext: data))
        XCTAssertFalse(VaultCrypto.objectIdMatches(id12, ciphertext: Data("other".utf8)))
        XCTAssertEqual(VaultCrypto.objectIdWidth("obj-cas-imm-xyz"), 0)
        XCTAssertEqual(VaultCrypto.objectIdWidth("obj-cas-imm-0123456789ab0"), 0)
        XCTAssertEqual(VaultCrypto.objectIdWidth("ref-pid-muw-0123456789ab"), 0)
    }

    func testEveryFixtureObjectHashesToItsName() throws {
        for fixture in Fixture.all {
            for url in try fixture.objects() {
                let data = try Data(contentsOf: url)
                XCTAssertTrue(VaultCrypto.objectIdMatches(url.lastPathComponent, ciphertext: data), url.lastPathComponent)
            }
        }
    }

    func testZlib() throws {
        XCTAssertEqual(Zlib.adler32(Data("Wikipedia".utf8)), 0x11E6_0398)
        let text = Data(String(repeating: "PrompTugal fixture line.\n", count: 300).utf8)
        let packed = try XCTUnwrap(Zlib.compress(text))
        XCTAssertLessThan(packed.count, text.count / 5)
        XCTAssertEqual(Zlib.decompress(packed), text)
        var broken = packed
        broken[broken.count - 1] ^= 0xFF                       // bad Adler-32
        XCTAssertNil(Zlib.decompress(broken))
        XCTAssertNil(Zlib.decompress(Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])))   // bad header
    }

    func testCanonicalJSONMatchesPython() throws {
        // Python: json.dumps(body, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
        let input = #"{"b": 1, "a": "Olá \"x\"\n\t\u0001/\\  ", "c": [null, true, false, -5, 1794019382461], "Z": {"y": "é"}, "signature": "drop", "user_signature": null}"#
        let expected = "{\"Z\":{\"y\":\"é\"},\"a\":\"Olá \\\"x\\\"\\n\\t\\u0001/\\\\ \u{2028}\",\"b\":1,\"c\":[null,true,false,-5,1794019382461]}"
        let bytes = try CanonicalJSON.signingBytes(commitJSON: Data(input.utf8))
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), expected)
    }

    func testClassifyHowTeamKeysArrive() {
        let hex = String(repeating: "ab", count: 32)
        // Pasted from chat or notes: surrounding spaces and newlines are fine.
        XCTAssertEqual(VaultKey.classify("  sgit_private_vault_abc123:fixtplain1\n"), .vault)
        XCTAssertEqual(VaultKey.classify("sgit_vk1_abc:fixtplain1"), .vault)                 // legacy prefix
        XCTAssertEqual(VaultKey.classify("sgit_rk1_\(hex):fixtplain1"), .privateRead)      // legacy prefix
        XCTAssertEqual(VaultKey.classify("\(hex):fixtplain1"), .bareRead)
        XCTAssertEqual(VaultKey.classify("passphrase24charsxxxxxxx:fixtplain1"), .vault)   // sgit's own key file form
        XCTAssertNil(VaultKey.classify("no colon at all"))
        // A 64-hex passphrase is read as a read key (sgit generates 24-character passphrases).
        XCTAssertEqual(VaultKey.classify("\(hex.uppercased()):fixtplain1"), .bareRead)
        XCTAssertEqual(VaultKey.classify("sgit_private_read_\(hex):fixtplain1"), .privateRead)
    }
}
