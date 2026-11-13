import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Recipients")
struct RecipientTests {
    static let link = DeveloperLane.builtInLink

    @Test func aLinkIsFoundInTextWithItsName() throws {
        let found = try #require(RecipientLink.read("scan this: \(Self.link)#Maria%20Silva and more"))
        #expect(found.link == Self.link)
        #expect(found.name == "Maria Silva")
        let bare = try #require(RecipientLink.read(Self.link))
        #expect(bare.name.isEmpty)
        #expect(RecipientLink.read("https://example.com/nothing-here") == nil)
        #expect(RecipientLink.read("sgi1.abcd.0123456789abcdef.tooshort") == nil)
    }

    @Test func whatIsWrittenIntoAQRCodeReadsBack() throws {
        let recipient = Recipient(name: "Claude (developer session)", link: Self.link)
        let text = RecipientLink.write(recipient)
        #expect(!text.contains(" "))
        let found = try #require(RecipientLink.read(text))
        #expect(found.link == recipient.link)
        #expect(found.name == recipient.name)
        #expect(RecipientLink.write(Recipient(name: "", link: Self.link)) == Self.link)
    }

    @Test func addingTheSameLinkAgainRenamesIt() {
        var list = RecipientLink.adding(name: "Maria", link: Self.link, to: [])
        list = RecipientLink.adding(name: "Maria Silva", link: Self.link, to: list)
        #expect(list == [Recipient(name: "Maria Silva", link: Self.link)])
        #expect(RecipientLink.adding(name: "", link: Self.link, to: []).first?.name == "Lane fjq2ekcw")
        #expect(RecipientLink.adding(name: "x", link: "not a link", to: list) == list)
    }

    @Test @MainActor func theBuiltInLaneIsFirstAndIsNotStoredTwice() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "recipients-\(UUID().uuidString).json")
        let store = RecipientStore(file: file)
        #expect(store.all.map(\.name) == [RecipientStore.builtInName])
        #expect(!store.add(name: "Me again", text: Self.link))
        #expect(!store.add(name: "Nobody", text: "hello"))
        #expect(store.added.isEmpty)
        #expect(RecipientStore(file: file).all.count == 1)
    }

    @Test @MainActor func aQRCodeDrawnHereIsReadHere() throws {
        let text = RecipientLink.write(Recipient(name: "Maria Silva", link: Self.link))
        let image = try #require(QRCode.image(for: text))
        let data = try #require(image.pngData())
        #expect(QRCode.read(imageData: data) == text)
    }
}
