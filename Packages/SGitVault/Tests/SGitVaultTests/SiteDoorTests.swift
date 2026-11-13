import CryptoKit
import Foundation
import XCTest
@testable import SGitVault

/// A door on another site. The vector is the published one, computed by sgit's own Python:
/// https://newsroom.sgit.ai/passkey/vectors.json (read 13 November 2026, sgit 0.21.0).
final class SiteDoorTests: XCTestCase {
    static let site = "newsroom.sgit.ai"
    static let prfHex = "3db9c5ab5757e5b579d4d91619c50789e1e60fd0367de86fcc4f444825af6664"

    func testNewsroomVector() throws {
        let prf = try XCTUnwrap(Data(hexString: Self.prfHex))
        let door = VaultDoor.door(fromSecret: prf, site: Self.site)
        XCTAssertEqual(door.passphrase, "9e4089399c4f9c05f10e76269d04eb81cf8c1d72a428b2f1557d09aef406076a")
        XCTAssertEqual(door.vaultId, "tem5tsyl")
        XCTAssertEqual(door.vaultKeyText,
                       "sgit_private_vault_9e4089399c4f9c05f10e76269d04eb81cf8c1d72a428b2f1557d09aef406076a:tem5tsyl")
    }

    func testNewsroomVectorKeys() throws {
        let prf = try XCTUnwrap(Data(hexString: Self.prfHex))
        let door = VaultDoor.door(fromSecret: prf, site: Self.site)
        let read = VaultCrypto.deriveReadKey(passphrase: door.passphrase, vaultId: door.vaultId)
        let write = VaultCrypto.deriveWriteKey(passphrase: door.passphrase, vaultId: door.vaultId)
        XCTAssertEqual(read.withUnsafeBytes { Data($0).hexString },
                       "5a4b5bdc67a4a81485f93b1455e11df77cb304b7b73c278c376565418802dc9d")
        XCTAssertEqual(write.withUnsafeBytes { Data($0).hexString },
                       "00c87e216e76e814aa1b5e642d75c9745e048dd90ad20c6b4a7aeff579697604")
    }

    func testTheDefaultSiteIsUnchanged() throws {
        let ikm = Data(repeating: 1, count: 32)
        let a = VaultDoor.door(fromSecret: ikm)
        let b = VaultDoor.door(fromSecret: ikm, site: VaultDoor.rpForDerivation)
        XCTAssertEqual(a.vaultId, b.vaultId)
        XCTAssertEqual(a.passphrase, b.passphrase)
    }

    func testSitesGiveDifferentDoors() throws {
        let ikm = Data(repeating: 1, count: 32)
        XCTAssertNotEqual(VaultDoor.door(fromSecret: ikm, site: VaultDoor.pkiSite).vaultId,
                          VaultDoor.door(fromSecret: ikm).vaultId)
        XCTAssertEqual(VaultDoor.prfSalt(site: VaultDoor.rpForDerivation), VaultDoor.prfSalt)
    }
}
