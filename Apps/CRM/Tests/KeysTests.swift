import Foundation
import SGitPeople
import Testing
@testable import CRM

/// W12 on two devices in one process: each makes keys (2048-bit here, for speed; the app makes 4096), one
/// scans the other's card, and the card's key goes onto a person record. All names are invented.
@MainActor
struct KeysTests {
    func device() -> KeysModel {
        KeysModel(peopleKeychain: MemoryKeychain(), secretsKeychain: MemoryKeychain(), folder: nil, rsaBits: 2048)
    }

    @Test func aCardScannedBecomesAPersonWithTheirKey() async throws {
        let me = device(), them = device()
        #expect(throws: KeysProblem.noKeysYet) { try me.addCard("anything", inPerson: true) }
        await me.makeIdentity(name: "Owner Example")
        await them.makeIdentity(name: "Ana Exemplo")
        let card = try #require(them.hub?.myCardText)

        let contact = try me.addCard(card, inPerson: true)
        #expect(contact.card.name == "Ana Exemplo")
        #expect(contact.met == .inPerson)
        #expect(contact.card.fingerprint == them.hub?.identity.bundle.fingerprint)

        let actor = Actor.person("Owner Example", key: "0011223344556677")
        let fresh = CardLink.person(for: contact, existing: [], by: actor, at: Invented.later)
        #expect(fresh.name.value == "Ana Exemplo")
        #expect(fresh.problems().isEmpty)
        #expect(CardLink.has(fresh, contact))
        #expect(fresh.links.first?.source?.saidBy.hasPrefix("Their contact card") == true)

        // Someone of the same name already in the CRM gets the key added, once.
        let updated = CardLink.person(for: contact, existing: [Invented.ana], by: actor, at: Invented.later)
        #expect(updated.id == Invented.anaID)
        #expect(CardLink.has(updated, contact))
        #expect(updated.emails == Invented.ana.emails)
        #expect(updated.changed.by == actor)
        let again = CardLink.person(for: contact, existing: [updated], by: actor, at: Invented.later)
        #expect(again.links.filter { $0.value == CardLink.value(contact) }.count == 1)
    }

    @Test func aChangedCardIsRefused() async throws {
        let me = device(), them = device()
        await me.makeIdentity(name: "Owner Example")
        await them.makeIdentity(name: "Tom Sample")
        let card = try #require(them.hub?.myCardText)
        var broken = Array(card)
        let i = broken.count - 5
        broken[i] = broken[i] == "A" ? "B" : "A"
        #expect(throws: (any Error).self) { try me.addCard(String(broken), inPerson: true) }
        #expect(me.hub?.contacts.isEmpty == true)
    }
}
