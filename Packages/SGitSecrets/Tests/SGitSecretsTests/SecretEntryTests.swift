import Foundation
import XCTest
@testable import SGitSecrets

/// The secret format and the password maker, now in their own package. SGit Vaults' own tests
/// (Apps/SGit/Tests/SecretsTests.swift) still run unchanged against the same types through the app.
final class SecretEntryTests: XCTestCase {
    /// A file as SGit Vaults has written it since 14 November 2026 must still open.
    func testAFileWrittenBeforeTheMoveStillOpens() throws {
        let written = Data("""
        {"changedBy":"key-rnd-imm-0123456789abcdef","createdAt":"2027-01-15T08:00:00Z","fields":[\
        {"hidden":false,"label":"Network","value":"Office"},{"hidden":true,"label":"Password","value":"sample"}],\
        "format":"sgit.ai/secret/v1","id":"3f2a","kind":"wifi","name":"Office Wi-Fi","note":"",\
        "updatedAt":"2027-01-15T09:30:00Z"}
        """.utf8)
        let entry = try SecretEntry.decode(written)
        XCTAssertEqual(entry.id, "3f2a")
        XCTAssertEqual(entry.kind, .wifi)
        XCTAssertEqual(entry.fields.map(\.label), ["Network", "Password"])
        XCTAssertEqual(entry.fields.map(\.hidden), [false, true])
        XCTAssertEqual(entry.changedBy, "key-rnd-imm-0123456789abcdef")
        XCTAssertEqual(entry.updatedAt, Date(timeIntervalSince1970: 1_800_005_400))
        XCTAssertEqual(entry.path, "secrets/3f2a.json")
        XCTAssertEqual(entry.subtitle, "Office")
        XCTAssertEqual(try SecretEntry.decode(try entry.encoded()), entry)
    }

    func testAnotherFormatIsRefused() {
        XCTAssertThrowsError(try SecretEntry.decode(Data(#"{"format":"something/else","id":"x"}"#.utf8)))
    }

    func testANewEntryHasItsKindsEmptyFields() {
        let entry = SecretEntry.new(.login, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entry.fields.map(\.label), ["Website", "Username", "Password", "One-time code secret"])
        XCTAssertEqual(entry.fields.map(\.hidden), [false, false, true, true])
        XCTAssertTrue(entry.filled.isEmpty)
        XCTAssertEqual(entry.subtitle, "Login")
    }

    func testOnlyFilesDirectlyInTheSecretsFolderAreSecrets() {
        XCTAssertTrue(SecretEntry.isSecretPath("secrets/abc.json"))
        XCTAssertFalse(SecretEntry.isSecretPath("secrets/old/abc.json"))
        XCTAssertFalse(SecretEntry.isSecretPath("secrets/abc.txt"))
        XCTAssertFalse(SecretEntry.isSecretPath("stage/secrets/abc.json"))
    }

    func testMadePasswordsAreReadableAndEveryCharacterIsAllowed() {
        let made = PasswordMaker.make()
        XCTAssertEqual(made.count, 23)
        XCTAssertEqual(made.split(separator: "-").count, 4)
        XCTAssertTrue(made.allSatisfy { $0 == "-" || PasswordMaker.alphabet.contains($0) })
        XCTAssertNotEqual(made, PasswordMaker.make())
        XCTAssertEqual(PasswordMaker.make(groups: 2, groupSize: 3).count, 7)
    }
}
