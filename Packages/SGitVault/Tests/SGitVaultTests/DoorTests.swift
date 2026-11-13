import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// The passkey door, against vectors from door_vectors.py (a port of the website's door.js),
/// and the whole account path against the throwaway account fixture.
@MainActor
final class DoorTests: XCTestCase {
    struct Vectors: Decodable {
        struct Vector: Decodable {
            let ikm_hex: String
            let seed_hex: String
            let passphrase: String
            let vault_id: String
            let read_key_hex: String
        }
        let rp_for_derivation: String
        let prf_input_text: String
        let prf_input_sha256: String
        let recovery_code: String
        let recovery_bytes_hex: String
        let vectors: [Vector]
    }

    static let doorDir = Fixture.root.appending(path: "door", directoryHint: .isDirectory)
    static let accountDir = Fixture.root.appending(path: "account", directoryHint: .isDirectory)

    func vectors() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: Self.doorDir.appending(path: "vectors.json")))
    }

    func testConstantsMatchTheWebsite() throws {
        let v = try vectors()
        XCTAssertEqual(VaultDoor.rpForDerivation, v.rp_for_derivation)
        XCTAssertEqual(VaultDoor.prfInputText, v.prf_input_text)
        XCTAssertEqual(VaultDoor.prfSalt.hexString, v.prf_input_sha256)
    }

    func testDoorDerivation() throws {
        for vector in try vectors().vectors {
            let door = VaultDoor.door(fromSecret: Data(hexString: vector.ikm_hex)!)
            XCTAssertEqual(door.vaultId, vector.vault_id)
            XCTAssertEqual(door.passphrase, vector.passphrase)
            XCTAssertTrue(VaultKey.isValidVaultId(door.vaultId))
            XCTAssertFalse(door.description.contains(vector.passphrase))
        }
        // The read key through PBKDF2, for one vector (600,000 rounds).
        let first = try vectors().vectors[0]
        let key = VaultDoor.key(for: VaultDoor.door(fromSecret: Data(hexString: first.ikm_hex)!))
        XCTAssertEqual(key.readKey.withUnsafeBytes { Data($0).hexString }, first.read_key_hex)
        // Negative control: one bit of difference gives another door.
        var other = Data(hexString: first.ikm_hex)!
        other[0] ^= 0x01
        XCTAssertNotEqual(VaultDoor.door(fromSecret: other).vaultId, first.vault_id)
    }

    func testRecoveryCode() throws {
        let v = try vectors()
        XCTAssertEqual(VaultDoor.recoveryBytes(v.recovery_code)?.hexString, v.recovery_bytes_hex)
        XCTAssertEqual(VaultDoor.recoveryBytes(v.recovery_code.lowercased())?.hexString, v.recovery_bytes_hex)
        XCTAssertNil(VaultDoor.recoveryBytes("ABCD-EFGH"))
        XCTAssertNil(VaultDoor.recoveryBytes(""))
    }

    func testAccountUnlockDoorMasterReader() async throws {
        let log = VaultTrafficLog()
        let cache = temporaryCache()
        let transport = FolderVaultTransport(root: Self.accountDir, perVaultSubfolder: "server")
        let keys = try await VaultAccount.unlock(secret: Data(repeating: 1, count: 32), log: log) { key in
            SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey, cache: cache,
                            log: log, transport: transport)
        }
        XCTAssertEqual(keys.door.vaultId, "07qqefdr")
        XCTAssertEqual(keys.master.vaultId, "fixtmaster1")
        XCTAssertEqual(keys.reader?.vaultId, "fixtreader1")
        XCTAssertEqual(keys.doorCount, 1)
        XCTAssertNil(keys.accessToken)
        let reader = SGitVault(address: VaultAddress(vaultId: "fixtreader1"), readKey: keys.reader!.readKey,
                               cache: cache, log: log, transport: transport)
        let paths = try await reader.files().map(\.path)
        XCTAssertEqual(paths, ["README.md", "apps/schedule.json"])
        XCTAssertFalse(keys.description.contains("throwaway-fixture"))
    }

    func testAccountUnlockWithAnotherPasskeyFindsNoDoor() async throws {
        let log = VaultTrafficLog()
        let transport = FolderVaultTransport(root: Self.accountDir, perVaultSubfolder: "server")
        do {
            _ = try await VaultAccount.unlock(secret: Data(repeating: 2, count: 32), log: log) { key in
                SGitVault(address: VaultAddress(vaultId: key.vaultId), readKey: key.readKey,
                                cache: temporaryCache(), log: log, transport: transport)
            }
            XCTFail("another passkey must not open this account")
        } catch VaultError.vaultNotFoundOrWrongKey {
            // expected: no door at the derived address
        }
    }
}
