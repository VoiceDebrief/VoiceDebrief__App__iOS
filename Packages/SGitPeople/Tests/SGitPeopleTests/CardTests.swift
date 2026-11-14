import Foundation
import Testing
@testable import SGitPeople

@Suite("Contact cards")
struct CardTests {
    @Test func aCardChecksAndItsTextReadsBackTheSame() throws {
        let card = try People.card(People.ana, "Ana Lima", inbox: People.anaInbox)
        try card.check()
        let text = try card.text()
        #expect(text.hasPrefix("sgc1."))
        #expect(text.split(separator: ".").count == 5)
        let back = try ContactCard.parse(text)
        #expect(back == card)
        #expect(back.fingerprint == People.ana.bundle.fingerprint)
        #expect(back.signingFingerprint == People.ana.bundle.signingFingerprint)
        #expect(back.inbox == People.anaInbox)
        #expect(back.createdAt == "2026-11-14T09:53:20Z")
    }

    @Test func aNewcomersCardHasNoInbox() throws {
        let card = try People.card(People.ben, "Ben", inbox: nil)
        let back = try ContactCard.parse(try card.text())
        #expect(back.inbox == nil)
        #expect(back.statement["body"]?["inbox"] == nil)
    }

    @Test func aCardIsFoundInsideALinkOrAMessage() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        #expect(try ContactCard.parse(try card.link()) == card)
        #expect(try card.link().hasPrefix(ContactCard.linkBase + "#sgc1."))
        let whatsApp = "Hi, this is me: \(try card.text()) (scan it or paste it)"
        #expect(try ContactCard.parse(whatsApp) == card)
    }

    @Test func noCardIsNoCard() {
        #expect(throws: ContactCard.Failure.noCard) { try ContactCard.parse("nothing here") }
    }

    @Test func aChangedNameDoesNotCheck() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        var forged = card
        forged.name = "Ana (bank)"
        #expect(throws: ContactCard.Failure.badSignature) { try forged.check() }
        #expect(throws: ContactCard.Failure.badSignature) { try ContactCard.parse(try forged.text()) }
    }

    @Test func aChangedInboxDoesNotCheck() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        var forged = card
        forged.inbox = People.benInbox
        #expect(throws: ContactCard.Failure.badSignature) { try forged.check() }
    }

    @Test func anotherKeysSignatureDoesNotCheck() throws {
        let ana = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let eve = try People.card(People.eve, "Ana", inbox: People.anaInbox)
        var forged = ana
        forged.signature = eve.signature
        #expect(!forged.isSound)
    }

    @Test func theCardIsARegisterStatementThatChecksAsOne() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let statement = card.statement
        #expect(statement["type"] == .string("card"))
        #expect(statement["registry"] == .string("sgit.ai/people"))
        #expect(statement["signer"] == .string(People.ana.bundle.signingFingerprint))
        #expect(PKI.verifyStatement(statement, signPEM: People.ana.bundle.sign))
        let parsed = try PKIJSON(parsing: Data((statement.canonical + "\n").utf8))
        #expect(try ContactCard.fromStatement(parsed) == card)
    }

    @Test func aStatementWithAnExtraFieldIsRefused() throws {
        var statement = try People.card(People.ana, "Ana", inbox: nil).statement
        statement["note"] = .string("not signed")
        #expect(throws: ContactCard.Failure.self) { try ContactCard.fromStatement(statement) }
    }

    @Test func aNameIsOneLineOfAtMostEightyCharacters() throws {
        #expect(throws: ContactCard.Failure.badName) { try People.card(People.ana, "  ", inbox: nil) }
        #expect(throws: ContactCard.Failure.badName) { try People.card(People.ana, "Ana\nLima", inbox: nil) }
        #expect(throws: ContactCard.Failure.badName) { try People.card(People.ana, String(repeating: "a", count: 81), inbox: nil) }
        #expect(try People.card(People.ana, "  Ana  ", inbox: nil).name == "Ana")
        #expect(try People.card(People.ana, "Zoë 日本", inbox: nil).name == "Zoë 日本")
    }

    @Test func aCardStoresAsItsText() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let data = try JSONEncoder().encode([card])
        #expect(try JSONDecoder().decode([ContactCard].self, from: data) == [card])
        #expect(String(decoding: data, as: UTF8.self).contains("sgc1."))
    }

    @Test func theLaneLinkIsTheOneVoiceDebriefTakes() throws {
        let link = try People.anaInbox.laneLink(encryptPEM: People.ana.bundle.encrypt, name: "Ana")
        #expect(link.hasPrefix("sgi1.anainbox.00112233445566778899aabbccddeeff0011223344556677."))
        #expect(link.hasSuffix("#Ana"))
        let spki = try PKI.publicDER(People.ana.bundle.encrypt)
        #expect(link.contains(PKI.base64url(spki)))
    }

    @Test func anInboxAddressSaysWhatIsWrong() {
        #expect(People.anaInbox.problems.isEmpty)
        #expect(InboxAddress(server: "http://x.example", vault: "AB", append: "zz").problems.count == 3)
        #expect(InboxAddress(server: "https://dev.send.sgraph.ai/", vault: "abcd", append: String(repeating: "a", count: 48)).server
                == "https://dev.send.sgraph.ai")
        #expect(People.anaInbox.url("list")?.absoluteString == "https://dev.send.sgraph.ai/api/vault/append/list/anainbox")
    }

    /// Made by `tools/people/people.py` (Python, the `cryptography` package), with a made-up inbox: the other
    /// implementation's card must check here. Public material only.
    @Test func aCardMadeByPeoplePyChecks() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("card-made-by-people-py.txt")
        let card = try ContactCard.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(card.name == "Zoë (made by people.py)")
        #expect(card.fingerprint == "sha256:7fd896078dcc79f5")
        #expect(card.signingFingerprint == "sha256:06aad0bc0aeeba1e")
        #expect(card.inbox?.vault == "fixture1")
        #expect(PKI.problems(of: card.bundle).isEmpty)
        #expect(try card.text() + "\n" == (try String(contentsOf: url, encoding: .utf8)))
    }

    /// The real size: a 4096-bit key, as every install makes.
    @Test func aFullSizeCardFitsAQRCode() throws {
        let identity = try PKI.generate(label: "Full size", rsaBits: 4096)
        let card = try ContactCard.make(name: "A long name for the size test", identity: identity, inbox: People.anaInbox)
        let text = try card.text()
        #expect(text.utf8.count < 1400)          // a QR code holds 2,953 bytes at its largest
        #expect(try ContactCard.parse(text) == card)
        #expect(PeopleQR.image(text) != nil)
    }
}

@Suite("Contacts")
struct ContactBookTests {
    @Test func aCardIsAddedOnceAndALaterOneUpdatesIt() throws {
        let book = ContactBook(file: nil)
        let first = try People.card(People.ben, "Ben", inbox: nil)
        #expect(try book.add(first, met: .inPerson, at: People.now) == .new(Contact(card: first, met: .inPerson, metAt: People.now)))
        #expect(try book.add(first, met: .byMessage).contact.met == .inPerson)
        if case .unchanged = try book.add(first, met: .byMessage) {} else { Issue.record("the same card changed something") }
        let later = try People.card(People.ben, "Ben Sousa", inbox: People.benInbox, at: People.now.addingTimeInterval(60))
        guard case .updated(let updated) = try book.add(later, met: .throughInbox, at: People.now) else {
            Issue.record("a later card did not update")
            return
        }
        #expect(updated.card.inbox == People.benInbox)
        #expect(updated.name == "Ben Sousa")
        #expect(updated.met == .inPerson)
        #expect(book.all.count == 1)
        if case .unchanged = try book.add(first, met: .byMessage) {} else { Issue.record("an older card replaced a newer one") }
    }

    @Test func aCardWithAKnownFingerprintButOtherKeysIsRefused() throws {
        let book = ContactBook(file: nil)
        try book.add(try People.card(People.ben, "Ben", inbox: nil), met: .inPerson)
        // Ben's encryption key (so Ben's fingerprint) with Eve's signing key: a sound card in itself, signed by Eve.
        let mixed = PKI.bundle(encryptSPKI: try PKI.publicDER(People.ben.bundle.encrypt),
                               signSPKI: try PKI.publicDER(People.eve.bundle.sign), label: "Ben")
        let eveAsBen = PKIIdentity(bundle: mixed, encryptPKCS8: People.eve.encryptPKCS8, signPKCS8: People.eve.signPKCS8,
                                   created: People.now)
        let forged = try ContactCard.make(name: "Ben", identity: eveAsBen, inbox: People.anaInbox, at: People.now.addingTimeInterval(60))
        try forged.check()
        #expect(throws: ContactBook.Failure.keysChanged(name: "Ben")) { try book.add(forged, met: .byMessage) }
        #expect(book.all.first?.card.inbox == nil)
    }

    @Test func anotherPersonWithTheSameNameIsAnotherContact() throws {
        let book = ContactBook(file: nil)
        try book.add(try People.card(People.ben, "Ben", inbox: nil), met: .inPerson)
        try book.add(try People.card(People.eve, "Ben", inbox: nil), met: .byMessage)
        #expect(book.all.count == 2)
    }

    @Test func yourOwnCardIsNotAContact() throws {
        let book = ContactBook(file: nil)
        let mine = try People.card(People.ana, "Ana", inbox: nil)
        #expect(throws: ContactBook.Failure.isMe) { try book.add(mine, met: .inPerson, myFingerprint: People.ana.bundle.fingerprint) }
    }

    @Test func contactsSurviveAReopen() throws {
        let file = People.temporaryFolder().appendingPathComponent("contacts.json")
        let book = ContactBook(file: file)
        try book.add(try People.card(People.ben, "Ben", inbox: People.benInbox), met: .inPerson, at: People.now)
        try book.add(try People.card(People.ana, "Ana", inbox: People.anaInbox), met: .byMessage, at: People.now, isAgent: true)
        book.rename(People.ben.bundle.fingerprint, to: "Benjamin")
        book.markVerified(People.ben.bundle.fingerprint, at: People.now)
        book.recordCardSent(to: People.ana.bundle.fingerprint, at: People.now)

        let reopened = ContactBook(file: file)
        #expect(reopened.all.map(\.name) == ["Ana", "Benjamin"])
        let ben = try #require(reopened.contact(People.ben.bundle.fingerprint))
        #expect(ben.verifiedAt == People.now)
        #expect(ben.met == .inPerson)
        #expect(ben.canReceive)
        let ana = try #require(reopened.contact(signingFingerprint: People.ana.bundle.signingFingerprint))
        #expect(ana.isAgent)
        #expect(ana.sentMyCardAt == People.now)
        #expect(reopened.bundles.count == 2)
        reopened.remove(People.ana.bundle.fingerprint)
        #expect(ContactBook(file: file).all.count == 1)
    }
}
