import Foundation
import XCTest
@testable import SGitVault

final class PicksAndLanesTests: XCTestCase {
    let vault = Data(#"{"v":1,"picks":[{"id":"events/a","at":"2025-11-09T01:00:00.000Z"},{"id":"events/b","at":1762650000000}]}"#.utf8)

    func testUnionKeepsTheVaultEntryAndAddsLocalOnes() throws {
        let local = Data(#"{"v":1,"picks":[{"at":"2099-01-01T00:00:00.000Z","id":"events/a"},{"id":"events/c","at":"2025-11-10T09:00:00.000Z"}]}"#.utf8)
        let merged = try VaultPicks.union(vault: vault, local: local)
        XCTAssertEqual(try VaultPicks.ids(merged), ["events/a", "events/b", "events/c"])
        // The website's form: v first, then picks; id before at; compact; `at` kept as given (string or number).
        XCTAssertEqual(String(decoding: merged, as: UTF8.self),
                       #"{"v":1,"picks":[{"id":"events/a","at":"2025-11-09T01:00:00.000Z"},{"id":"events/b","at":1762650000000},{"id":"events/c","at":"2025-11-10T09:00:00.000Z"}]}"#)
    }

    func testNoVaultCopyYetGivesTheLocalPicks() throws {
        let local = Data(#"{"v":1,"picks":[{"id":"events/x","at":"2025-11-09T01:00:00.000Z"}]}"#.utf8)
        XCTAssertEqual(try VaultPicks.ids(VaultPicks.union(vault: nil, local: local)), ["events/x"])
        XCTAssertEqual(try VaultPicks.ids(VaultPicks.union(vault: Data(), local: local)), ["events/x"])
    }

    func testDuplicatesAndEntriesWithoutIdsAreDropped() throws {
        let local = Data(#"{"v":1,"picks":[{"id":"events/b","at":1},{"at":2},{"id":"","at":3},"junk",{"id":"events/d","at":4},{"id":"events/d","at":5}]}"#.utf8)
        let merged = try VaultPicks.union(vault: vault, local: local)
        XCTAssertEqual(try VaultPicks.ids(merged), ["events/a", "events/b", "events/d"])
        XCTAssertTrue(String(decoding: merged, as: UTF8.self).contains(#"{"id":"events/d","at":4}"#))
    }

    func testExtraMembersAreKept() throws {
        let local = Data(#"{"v":1,"picks":[{"note":"bring badge","id":"events/n","at":"2025-11-09T01:00:00.000Z"}]}"#.utf8)
        let merged = String(decoding: try VaultPicks.union(vault: nil, local: local), as: UTF8.self)
        XCTAssertEqual(merged, #"{"v":1,"picks":[{"id":"events/n","at":"2025-11-09T01:00:00.000Z","note":"bring badge"}]}"#)
    }

    func testMalformedDocumentsThrowInsteadOfOverwriting() {
        let good = Data(#"{"v":1,"picks":[]}"#.utf8)
        for bad in ["not json", "[1,2]", #"{"v":1,"picks":"nope"}"#] {
            XCTAssertThrowsError(try VaultPicks.union(vault: Data(bad.utf8), local: good), bad) { error in
                guard let e = error as? VaultError, case .malformed = e else { return XCTFail("\(error)") }
            }
            XCTAssertThrowsError(try VaultPicks.union(vault: good, local: Data(bad.utf8)), bad)
        }
    }

    func testLaneFileNamesSortByTimeAndAreSafe() {
        let early = Date(timeIntervalSince1970: 1_794_000_000)
        let late = early.addingTimeInterval(61)
        let a = VaultLanes.fileName(at: early, device: "device-AB12cd34", suffix: "0001")
        let b = VaultLanes.fileName(at: late, device: "device-ab12cd34", suffix: "0000")
        XCTAssertEqual(a, "20261106T212000Z-device-ab12cd34-0001.json")
        XCTAssertLessThan(a, b)
        XCTAssertEqual(VaultLanes.fileName(at: early, device: "../evil/x", suffix: "z"), "20261106T212000Z----evil-x-z.json")
        XCTAssertNotEqual(VaultLanes.fileName(device: "d"), VaultLanes.fileName(device: "d"))   // random suffix
        XCTAssertEqual(VaultLanes.path(folder: "lanes/team/", name: "f.json"), "lanes/team/f.json")
        XCTAssertEqual(VaultLanes.path(folder: "", name: "f.json"), "f.json")
    }
}
