#if DEBUG
import Foundation
import SGitPeople

/// People for the pictures of the screens (`-SGScreen people-…`), made by the real engine with throwaway keys,
/// kept in memory: cards signed, messages sealed and opened as they would be, secrets in a Keychain in memory.
/// No network and no server answer: the inbox's messages are opened from payloads sealed here.
extension PeopleModel {
    enum SampleState: String {
        /// Nothing made yet: the screen that offers to make keys.
        case empty
        /// Keys, an inbox, three contacts, three messages (one a secret), two secrets.
        case full
    }

    static func sample(_ state: SampleState) -> PeopleModel {
        let model = PeopleModel(peopleKeychain: MemoryKeychain(), secretsKeychain: MemoryKeychain(), folder: nil)
        guard state == .full else { return model }
        // RSA 2048 keeps the pictures quick; every key here is thrown away with the process.
        guard let me = try? PeopleIdentity.loadOrMake(MemoryKeychain(), label: "Sam", rsaBits: 2048),
              let ana = try? PKI.generate(label: "Ana", rsaBits: 2048),
              let ben = try? PKI.generate(label: "Ben", rsaBits: 2048),
              let claude = try? PKI.generate(label: "Claude (developer)", rsaBits: 2048) else { return model }
        let inbox = InboxAddress(vault: "samsinbox", append: String(repeating: "5a", count: 24))
        let secrets = SecretsStore(keychain: MemoryKeychain())
        try? secrets.saveInbox(InboxKeys(address: inbox, enumKey: String(repeating: "e", count: 64), vaultKey: "sample"))
        let hub = PeopleHub(identity: me, name: "Sam", folder: nil, secrets: secrets)
        let now = Date()
        func card(_ who: PKIIdentity, _ name: String, _ vault: String?) -> ContactCard? {
            try? ContactCard.make(name: name, identity: who, inbox: vault.map { InboxAddress(vault: $0, append: String(repeating: "7c", count: 24)) },
                                  at: now.addingTimeInterval(-86_400))
        }
        if let a = card(ana, "Ana Lima", "anasinbox") { try? hub.book.add(a, met: .inPerson, at: now.addingTimeInterval(-86_400 * 3)) }
        if let b = card(ben, "Ben", nil) { try? hub.book.add(b, met: .byMessage, at: now.addingTimeInterval(-3_600)) }
        if let c = card(claude, "Claude (developer)", "claudeinbox") { try? hub.book.add(c, met: .byMessage, at: now.addingTimeInterval(-86_400), isAgent: true) }
        hub.book.markVerified(ana.bundle.fingerprint, at: now.addingTimeInterval(-86_400 * 3))

        func arrived(_ from: PKIIdentity, _ message: PeopleMessage, _ id: String, _ ago: TimeInterval) -> ReceivedMessage? {
            guard let payload = try? message.lanePayload(to: me.bundle, from: from) else { return nil }
            return InboxCheck.receive(fileId: id, content: payload, received: now.addingTimeInterval(-ago), me: me, contacts: hub.book.bundles)
        }
        let to = me.bundle.signingFingerprint
        let access = SharedSecret(id: "sample-access", kind: .accessKey, name: "dev.send.sgraph.ai", value: "sample-not-a-key",
                                  server: InboxAddress.defaultServer)
        let received = [
            arrived(ana, PeopleMessage(kind: .text, from: ana.bundle.signingFingerprint, to: to, text: "The photos from Saturday are in our shared vault."), "s1", 600),
            arrived(claude, PeopleMessage(kind: .text, from: claude.bundle.signingFingerprint, to: to, replyTo: "note-1",
                                          text: "Thanks for the note: the record button is now at the top."), "s2", 3_600 * 5),
            arrived(ana, PeopleMessage(kind: .secret, from: ana.bundle.signingFingerprint, to: to, secret: access), "s3", 86_400 * 2),
        ].compactMap { $0 }
        try? hub.store.add(received)
        hub.store.markRead("s3")
        if let kept = try? secrets.add(kind: .password, name: "Office Wi-Fi", value: "sample-not-a-password", at: now.addingTimeInterval(-86_400 * 5)),
           let anaContact = hub.book.contact(ana.bundle.fingerprint) {
            try? secrets.recordShared(kept.id, with: anaContact, at: now.addingTimeInterval(-86_400 * 4))
            _ = try? secrets.change(kept.id, value: "sample-changed", at: now.addingTimeInterval(-86_400))
        }
        try? secrets.receive(access, from: SecretHolder(fingerprint: ana.bundle.fingerprint, name: "Ana Lima", at: now.addingTimeInterval(-86_400 * 2), version: 1))
        hub.reload()
        model.useSample(hub)
        return model
    }
}
#endif
