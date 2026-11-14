import Foundation
import Testing
@testable import SGitPeople

@Suite("The secrets store")
struct SecretsTests {
    func contact(_ who: PKIIdentity, _ name: String) throws -> Contact {
        Contact(card: try People.card(who, name, inbox: nil), met: .inPerson, metAt: People.now)
    }

    @Test func aSecretIsListedWithoutItsValue() throws {
        let store = SecretsStore(keychain: MemoryKeychain())
        let kept = try store.add(kind: .password, name: " Wi-Fi ", value: "correct horse", at: People.now)
        #expect(kept.name == "Wi-Fi")
        #expect(kept.version == 1)
        #expect(store.all == [kept])
        #expect(store.value(kept.id) == "correct horse")
        #expect(throws: SecretsStore.Failure.emptyValue) { try store.add(kind: .note, name: "x", value: "") }
    }

    @Test func aChangeRaisesTheVersionAndNamesWhoHoldsTheOldOne() throws {
        let store = SecretsStore(keychain: MemoryKeychain())
        let kept = try store.add(kind: .apiToken, name: "Token", value: "v1", at: People.now)
        let ben = try contact(People.ben, "Ben")
        try store.recordShared(kept.id, with: ben, at: People.now)
        #expect(store.meta(kept.id)?.heldBy.map(\.name) == ["Ben"])
        #expect(store.meta(kept.id)?.holdersOfAnOlderVersion.isEmpty == true)
        let changed = try store.change(kept.id, value: "v2", at: People.now.addingTimeInterval(60))
        #expect(changed.version == 2)
        #expect(changed.holdersOfAnOlderVersion.map(\.fingerprint) == [ben.id])
        #expect(store.value(kept.id) == "v2")
        try store.recordShared(kept.id, with: ben)
        #expect(store.meta(kept.id)?.heldBy.count == 1)
        #expect(store.meta(kept.id)?.holdersOfAnOlderVersion.isEmpty == true)
    }

    @Test func whatIsSharedIsTheCurrentValue() throws {
        let store = SecretsStore(keychain: MemoryKeychain())
        let kept = try store.add(kind: .accessKey, name: "dev", value: "a", server: "https://dev.send.sgraph.ai")
        try store.change(kept.id, value: "b")
        let out = try store.outgoing(kept.id)
        #expect(out == SharedSecret(id: kept.id, kind: .accessKey, name: "dev", value: "b", server: "https://dev.send.sgraph.ai", version: 2))
    }

    @Test func aReceivedSecretRemembersWhoSentItAndALaterVersionReplacesIt() throws {
        let store = SecretsStore(keychain: MemoryKeychain())
        let ana = SecretHolder(fingerprint: People.ana.bundle.fingerprint, name: "Ana", at: People.now, version: 1)
        let v1 = SharedSecret(id: "ana-1", kind: .accessKey, name: "dev", value: "old", server: "https://dev.send.sgraph.ai", version: 1)
        let first = try store.receive(v1, from: ana, at: People.now)
        #expect(first.receivedFrom?.name == "Ana")
        #expect(store.accessKey(for: "https://dev.send.sgraph.ai/") == "old")
        #expect(try store.receive(v1, from: ana).id == first.id)
        #expect(store.all.count == 1)
        var v2 = v1
        v2.value = "new"
        v2.version = 2
        let second = try store.receive(v2, from: ana, at: People.now.addingTimeInterval(60))
        #expect(second.id == first.id)
        #expect(second.receivedFrom?.version == 2)
        #expect(store.value(first.id) == "new")
        // The same id from someone else is another secret.
        let eve = SecretHolder(fingerprint: People.eve.bundle.fingerprint, name: "Eve", at: People.now, version: 1)
        try store.receive(v1, from: eve)
        #expect(store.all.count == 2)
    }

    @Test func secretsGoToICloudKeychainUnlessTheSwitchIsOff() throws {
        let cloud = MemoryCloudKeychain()
        let phone = MemoryKeychain(cloud: cloud), pad = MemoryKeychain(cloud: cloud)
        let onPhone = SecretsStore(keychain: phone)
        let kept = try onPhone.add(kind: .note, name: "n", value: "v")
        #expect(SecretsStore(keychain: pad).value(kept.id) == "v")
        onPhone.setSynchronise(false)
        #expect(!onPhone.synchronise)
        #expect(onPhone.value(kept.id) == "v")
        #expect(SecretsStore(keychain: pad).all.isEmpty)
        #expect(phone.accounts(.synchronised).isEmpty)
        onPhone.setSynchronise(true)
        #expect(SecretsStore(keychain: pad).value(kept.id) == "v")
        #expect(phone.accounts(.thisDeviceOnly).isEmpty)
    }

    @Test func removingTakesBothItems() throws {
        let keychain = MemoryKeychain()
        let store = SecretsStore(keychain: keychain)
        let kept = try store.add(kind: .vaultKey, name: "v", value: "k")
        store.remove(kept.id)
        #expect(store.all.isEmpty)
        #expect(keychain.accounts(.synchronised).isEmpty)
    }

    @Test func theInboxKeysAreKept() throws {
        let store = SecretsStore(keychain: MemoryKeychain())
        #expect(store.inbox == nil)
        try store.saveInbox(benKeys)
        #expect(store.inbox == benKeys)
        #expect(store.all.isEmpty)
    }
}
