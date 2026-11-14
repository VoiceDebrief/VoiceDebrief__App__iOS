import Foundation
import SGitVault
import Testing
@testable import SGitPeople

/// Section 5 of the article, end to end, with no network: a folder stands in for the vault server (the same
/// writes creation makes to the live one) and the lane's answers are the recorded ones.
@Suite("First contact")
struct FirstContactTests {
    /// Ana has the access key and an inbox; Ben has just installed the app.
    let accessKey = SharedSecret(id: "ana-access", kind: .accessKey, name: "dev.send.sgraph.ai",
                                 value: "access-key-for-the-test", server: "https://dev.send.sgraph.ai")

    @Test func theInvitationOpensOnlyForTheNewcomer() throws {
        let benCard = try People.card(People.ben, "Ben", inbox: nil)
        let anaCard = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let text = try FirstContact.invitation(accessKey: accessKey, to: benCard, from: People.ana, myCard: anaCard, at: People.now)
        #expect(text.hasPrefix("m1."))
        #expect(!text.contains("access-key-for-the-test"))
        let invitation = try FirstContact.open("Ana sent you: " + text, me: People.ben)
        #expect(invitation.accessKey == accessKey)
        #expect(invitation.inviter == anaCard)
        #expect(invitation.opened.trust == .cardInside)
        #expect(throws: PeopleMessage.OpenFailure.notForMe) { try FirstContact.open(text, me: People.eve) }
        #expect(throws: FirstContact.Failure.notAnInvitation) { try FirstContact.open("hello", me: People.ben) }
    }

    @Test func inPersonTheInvitationNeedNotCarryTheInvitersCard() async throws {
        let benCard = try People.card(People.ben, "Ben", inbox: nil)
        let anaCard = try People.card(People.ana, "Ana", inbox: People.anaInbox)
        let small = try FirstContact.invitation(accessKey: accessKey, to: benCard, from: People.ana, myCard: nil, at: People.now)
        let large = try FirstContact.invitation(accessKey: accessKey, to: benCard, from: People.ana, myCard: anaCard, at: People.now)
        #expect(small.utf8.count < 2_600)
        #expect(large.utf8.count > small.utf8.count + 1_000)
        #expect(PeopleQR.image(small) != nil)
        // Ben scanned Ana's card first: the invitation checks against it, and accept finds her there.
        let benContacts = ContactBook(file: nil)
        try benContacts.add(anaCard, met: .inPerson, at: People.now)
        let invitation = try FirstContact.open(small, me: People.ben, contacts: benContacts.bundles)
        #expect(invitation.opened.trust == .contact)
        #expect(invitation.inviter == nil)
        let http = ReplayLaneHTTP([("configure", 200, RecordedLane.configured), ("write", 200, RecordedLane.writeOK)])
        _ = try await FirstContact.accept(invitation, name: "Ben", me: People.ben, secrets: SecretsStore(keychain: MemoryKeychain()),
                                          contacts: benContacts,
                                          maker: InboxMaker(client: LaneClient(http: http), writer: FolderVaultTransport(root: People.temporaryFolder(), perVaultSubfolder: "")),
                                          client: LaneClient(http: http), signer: SoftwareCommitSigner(), how: .inPerson, at: People.now)
        #expect(http.call(1).url.lastPathComponent == "anainbox")
    }

    @Test func aMessageThatIsNotAnAccessKeyIsNotAnInvitation() throws {
        let note = PeopleMessage(kind: .text, from: People.ana.bundle.signingFingerprint, to: People.ben.bundle.signingFingerprint, text: "hi")
        let text = try note.sealedText(to: People.ben.bundle, from: People.ana)
        #expect(throws: FirstContact.Failure.notAnInvitation) { try FirstContact.open(text, me: People.ben) }
    }

    @Test func theWholeRoundTrip() async throws {
        // 1. Ben's first card: no inbox. Ana scans it.
        let benFirst = try People.card(People.ben, "Ben", inbox: nil)
        let anaContacts = ContactBook(file: nil)
        try anaContacts.add(try ContactCard.parse(try benFirst.text()), met: .inPerson, at: People.now)
        let anaCard = try People.card(People.ana, "Ana", inbox: People.anaInbox)

        // 2. Ana seals the access key to it.
        let text = try FirstContact.invitation(accessKey: accessKey, to: benFirst, from: People.ana, myCard: anaCard, at: People.now)

        // 3. Ben opens it and accepts: the access key kept, Ana added, an inbox made, the full card sent.
        let later = People.now.addingTimeInterval(60)
        let invitation = try FirstContact.open(text, me: People.ben)
        let server = People.temporaryFolder()
        let http = ReplayLaneHTTP([("configure", 200, RecordedLane.configured), ("write", 200, RecordedLane.writeOK)])
        let client = LaneClient(http: http)
        let benSecrets = SecretsStore(keychain: MemoryKeychain())
        let benContacts = ContactBook(file: nil)
        let benCard = try await FirstContact.accept(invitation, name: "Ben", me: People.ben, secrets: benSecrets, contacts: benContacts,
                                                    maker: InboxMaker(client: client, writer: FolderVaultTransport(root: server, perVaultSubfolder: "")),
                                                    client: client, signer: SoftwareCommitSigner(), how: .inPerson, at: later)
        #expect(benSecrets.accessKey(for: "https://dev.send.sgraph.ai") == "access-key-for-the-test")
        #expect(benSecrets.all.first?.receivedFrom?.name == "Ana")
        #expect(benContacts.contact(People.ana.bundle.fingerprint)?.card.inbox == People.anaInbox)
        #expect(benContacts.contact(People.ana.bundle.fingerprint)?.sentMyCardAt == later)
        let benKeys = try #require(benSecrets.inbox)
        #expect(benCard.inbox == benKeys.address)
        #expect(benKeys.address.problems.isEmpty)
        #expect(benKeys.vaultKey.hasSuffix(":" + benKeys.address.vault))

        // The vault exists where the server would hold it, and the lane was configured with its write key and the access key.
        let created = try FileManager.default.contentsOfDirectory(atPath: server.path)
        #expect(created == [benKeys.address.vault])
        let configure = http.call(0)
        #expect(configure.url.lastPathComponent == benKeys.address.vault)
        #expect(configure.headers["x-sgraph-access-token"] == "access-key-for-the-test")
        let parsed = try VaultKey.parse(benKeys.vaultKey)
        let writeKeyBytes = try #require(parsed.writeKey)
        let writeKey = writeKeyBytes.withUnsafeBytes { Data($0) }.hexString
        #expect(configure.headers["x-sgraph-vault-write-key"] == writeKey)
        #expect(configure.body["append_anchors"] as? [String] == [LaneClient.sha256Hex(benKeys.address.append)])

        // The card went to Ana's inbox.
        let write = http.call(1)
        #expect(write.url.absoluteString == "https://dev.send.sgraph.ai/api/vault/append/write/anainbox")
        #expect(write.body["append_token"] as? String == People.anaInbox.append)
        let payload = try #require(write.body["payload"] as? String)

        // 4. Ana's inbox check finds it; her contact for Ben gains the inbox.
        let received = InboxCheck.receive(fileId: RecordedLane.fileOne, content: payload, received: People.now, me: People.ana,
                                          contacts: anaContacts.bundles)
        #expect(received.trust == .contact)
        #expect(received.message?.kind == .card)
        guard case .updated(let ben)? = anaContacts.absorbCard(from: received, myFingerprint: People.ana.bundle.fingerprint) else {
            Issue.record("Ben's card did not update Ana's contact")
            return
        }
        #expect(ben.card.inbox == benKeys.address)
        #expect(ben.met == .inPerson)

        // Running accept again does not make a second inbox.
        let again = ReplayLaneHTTP([("write", 200, RecordedLane.writeOK)])
        _ = try await FirstContact.accept(invitation, name: "Ben", me: People.ben, secrets: benSecrets, contacts: benContacts,
                                          maker: InboxMaker(client: LaneClient(http: again), writer: FolderVaultTransport(root: server, perVaultSubfolder: "")),
                                          client: LaneClient(http: again), signer: SoftwareCommitSigner(), how: .inPerson, at: People.now)
        #expect(again.remaining == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: server.path).count == 1)
    }

    @Test func aCardFromAStrangerArrivesAsANewContactMetThroughTheInbox() throws {
        let eveCard = try People.card(People.eve, "Eve", inbox: People.benInbox)
        let (_, payload) = try FirstContact.cardMessage(eveCard, to: try People.card(People.ana, "Ana", inbox: People.anaInbox), from: People.eve)
        let book = ContactBook(file: nil)
        let received = InboxCheck.receive(fileId: "f", content: payload, received: People.now, me: People.ana, contacts: book.bundles)
        #expect(received.trust == .cardInside)
        #expect(book.absorbCard(from: received)?.contact.met == .throughInbox)
    }
}
