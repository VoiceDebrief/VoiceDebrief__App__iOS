import Foundation
import Testing
@testable import SGitPeople

@Suite("Messages: sealed, signed, opened")
struct MessageTests {
    func text(from: PKIIdentity, to: PKIIdentity, _ words: String = "Hello Ben", card: String? = nil) -> PeopleMessage {
        PeopleMessage(kind: .text, from: from.bundle.signingFingerprint, to: to.bundle.fingerprint, sentAt: People.now,
                      id: "0123456789abcdef0123456789abcdef", card: card, text: words)
    }

    @Test func aMessageFromAContactOpensAsFromThem() throws {
        let message = text(from: People.ana, to: People.ben)
        let sealed = try message.seal(to: People.ben.bundle, from: People.ana)
        let opened = try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.ana.bundle])
        #expect(opened.message == message)
        #expect(opened.trust == .contact)
        #expect(opened.signer == People.ana.bundle.signingFingerprint)
    }

    @Test func aMessageFromSomeoneUnknownIsUncheckedNotForged() throws {
        let sealed = try text(from: People.ana, to: People.ben).seal(to: People.ben.bundle, from: People.ana)
        let opened = try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [])
        #expect(opened.trust == .unknown)
    }

    @Test func aMessageCarryingTheSendersCardIsCheckedAgainstIt() throws {
        let card = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let sealed = try text(from: People.ana, to: People.ben, card: try card.text()).seal(to: People.ben.bundle, from: People.ana)
        let opened = try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [])
        #expect(opened.trust == .cardInside)
        #expect(opened.card == card)
    }

    @Test func someoneElsesCardInsideDoesNotVouchForTheSender() throws {
        let eveCard = try People.card(People.eve, "Eve", inbox: nil)
        let sealed = try text(from: People.ana, to: People.ben, card: try eveCard.text()).seal(to: People.ben.bundle, from: People.ana)
        #expect(try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: []).trust == .unknown)
    }

    @Test func aMessageSealedToSomeoneElseDoesNotOpen() throws {
        let sealed = try text(from: People.ana, to: People.eve).seal(to: People.eve.bundle, from: People.ana)
        #expect(throws: PeopleMessage.OpenFailure.notForMe) {
            try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.ana.bundle])
        }
    }

    @Test func aMessagePassedOnIsForged() throws {
        // Eve signs a message whose inside says it is from Ana: the signature is Eve's, so `from` does not match.
        let lying = text(from: People.ana, to: People.ben)
        let sealed = try PKI.seal(lying.json, to: People.ben.bundle, signedBy: People.eve)
        let opened = try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.ana.bundle, People.eve.bundle])
        #expect(opened.trust == .forged)
    }

    @Test func aMessageWrittenToSomeoneElseAndResealedIsForged() throws {
        // Ana wrote to Eve; Eve opens it and seals the same bytes to Ben, signed by Eve: `to` names Eve, not Ben.
        let toEve = text(from: People.eve, to: People.eve)
        let sealed = try PKI.seal(toEve.json, to: People.ben.bundle, signedBy: People.eve)
        #expect(try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.eve.bundle]).trust == .forged)
    }

    @Test func anUnsignedMessageSaysSo() throws {
        let sealed = try PKI.seal(text(from: People.ana, to: People.ben).json, to: People.ben.bundle)
        #expect(try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.ana.bundle]).trust == .unsigned)
    }

    @Test func sealingChecksFromAndTo() throws {
        #expect(throws: PKIError.self) { try text(from: People.ana, to: People.ben).seal(to: People.eve.bundle, from: People.ana) }
        #expect(throws: PKIError.self) { try text(from: People.ana, to: People.ben).seal(to: People.ben.bundle, from: People.eve) }
    }

    @Test func eachKindNeedsItsPart() {
        let from = People.ana.bundle.signingFingerprint, to = People.ben.bundle.fingerprint
        #expect(!PeopleMessage(kind: .text, from: from, to: to).problems.isEmpty)
        #expect(!PeopleMessage(kind: .secret, from: from, to: to).problems.isEmpty)
        #expect(!PeopleMessage(kind: .card, from: from, to: to).problems.isEmpty)
        #expect(!PeopleMessage(kind: .vaultInvitation, from: from, to: to).problems.isEmpty)
        #expect(!PeopleMessage(kind: .voiceNote, from: from, to: to).problems.isEmpty)
        let note = VoiceNoteReference(vault: "abcd1234", path: "debriefs/2026/11/14/x/audio.m4a", title: "Standup", seconds: 42)
        #expect(PeopleMessage(kind: .voiceNote, from: from, to: to, voiceNote: note).problems.isEmpty)
    }

    @Test func theJSONIsSortedSnakeCase() throws {
        let json = String(decoding: text(from: People.ana, to: People.ben).json, as: UTF8.self)
        #expect(json.hasPrefix("{\"format\":\"sgit.ai/people/message/v1\",\"from\":\"sha256:"))
        #expect(json.contains("\"sent_at\":\"2026-11-14T09:53:20Z\""))
        #expect(!json.contains("replyTo"))
    }

    @Test func aSealedTextOpensFromALinkOrAMessage() throws {
        let message = text(from: People.ana, to: People.ben)
        let sealedText = try message.sealedText(to: People.ben.bundle, from: People.ana)
        #expect(sealedText.hasPrefix("sgm1."))
        for wrapped in [sealedText, SealedText.link(sealedText), "Open this: \(sealedText) thanks"] {
            let envelope = try #require(SealedText.envelope(in: wrapped))
            #expect(try PeopleMessage.open(envelope: envelope, me: People.ben, contacts: [People.ana.bundle]).message == message)
        }
        #expect(SealedText.envelope(in: "sgm1.") == nil)
    }

    @Test func aLanePayloadIsTheEnvelopeEncodedOnceMore() throws {
        let message = text(from: People.ana, to: People.ben)
        let payload = try message.lanePayload(to: People.ben.bundle, from: People.ana)
        let encText = try LaneCrypto.encText(fromLaneContent: payload)
        #expect(Data(base64Encoded: encText) != nil)
        #expect(try PeopleMessage.open(laneContent: payload, me: People.ben, contacts: [People.ana.bundle]).trust == .contact)
    }

    @Test func aSecretTravelsWhole() throws {
        let secret = SharedSecret(id: "s1", kind: .accessKey, name: "dev server", value: "not-a-real-access-key",
                                  server: "https://dev.send.sgraph.ai", version: 3)
        let message = PeopleMessage(kind: .secret, from: People.ana.bundle.signingFingerprint, to: People.ben.bundle.fingerprint,
                                    secret: secret)
        let sealed = try message.seal(to: People.ben.bundle, from: People.ana)
        #expect(!sealed.contains("not-a-real-access-key"))
        #expect(try PeopleMessage.open(envelope: sealed, me: People.ben, contacts: [People.ana.bundle]).message.secret == secret)
    }
}
