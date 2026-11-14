import Foundation
import Testing
@testable import SGit

@Suite("Secrets kept as files in vaults")
struct SecretsTests {
    @Test func anEntryRoundTripsAndKeepsOnlyFilledFieldsWhenSaved() throws {
        var entry = SecretEntry.new(.wifi, at: Date(timeIntervalSince1970: 1_800_000_000))
        entry.name = "Office Wi-Fi"
        entry.fields[0].value = "SGit-Office"
        entry.fields[1].value = "sample-password"
        let back = try SecretEntry.decode(try entry.encoded())
        #expect(back == entry)
        #expect(back.path == "secrets/\(entry.id).json")
        #expect(back.subtitle == "SGit-Office")
        #expect(back.fields[1].hidden)
        var empty = SecretEntry.new(.login)
        empty.fields[1].value = "ana"
        #expect(empty.filled.map(\.label) == ["Username"])
    }

    @Test func onlyFilesDirectlyInTheSecretsFolderAreSecrets() {
        #expect(SecretEntry.isSecretPath("secrets/abc.json"))
        #expect(!SecretEntry.isSecretPath("secrets/old/abc.json"))
        #expect(!SecretEntry.isSecretPath("secrets/abc.txt"))
        #expect(!SecretEntry.isSecretPath("stage/secrets/abc.json"))
    }

    @Test func aFileOfAnotherFormatIsRefused() {
        let other = Data(#"{"format":"something/else","id":"x"}"#.utf8)
        #expect(throws: (any Error).self) { try SecretEntry.decode(other) }
    }

    @Test func everyKindHasFieldsAndAtLeastOneHiddenOneExceptWhereNothingIsSecret() {
        for kind in SecretKindOfEntry.allCases {
            #expect(!kind.template.isEmpty)
            #expect(kind.template.contains { $0.hidden })
            #expect(!kind.words.isEmpty)
        }
    }

    @Test func madePasswordsAreLongReadableAndDifferent() {
        let one = PasswordMaker.make()
        let two = PasswordMaker.make()
        #expect(one.count == 23)
        #expect(one.split(separator: "-").count == 4)
        #expect(one != two)
        #expect(one.allSatisfy { $0 == "-" || PasswordMaker.alphabet.contains($0) })
        #expect(!one.contains("0") && !one.contains("O") && !one.contains("l"))
    }

    @Test func theQuestionsShipWithTheAppAndAnAnswerIsOneLaneMessage() throws {
        let all = OwnerQuestion.bundled()
        #expect(all.count >= 5)
        #expect(Set(all.map(\.id)).count == all.count)
        let message = try OwnerQuestion.laneMessage(question: all[0], choice: all[0].options.first, words: "said aloud",
                                                    app: "sgit 0.0.0 (0)", device: "test",
                                                    at: Date(timeIntervalSince1970: 1_800_000_000))
        let newline = try #require(message.firstIndex(of: 0x0A))
        let header = try JSONDecoder().decode(DeveloperLane.Header.self, from: message[..<newline])
        #expect(header.kind == "sgit/answer/v1")
        #expect(header.name == "answer.json")
    }
}
