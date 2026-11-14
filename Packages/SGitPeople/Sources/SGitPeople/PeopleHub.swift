import Foundation
import Observation
import SGitVault

/// The person's own key bundle, kept in the Keychain (iCloud Keychain by default, so their other devices are
/// the same person). Made once, on first use. For an app that has no identity of its own yet; VoiceDebrief's
/// `IdentityBook` keeps its own and hands it to `PeopleHub`.
public enum PeopleIdentity {
    static let account = "identity.bundle"

    public static func load(_ keychain: any PeopleKeychain) -> PKIIdentity? {
        for home in [KeychainHome.synchronised, .thisDeviceOnly] {
            if let data = keychain.get(account, home), let identity = try? JSONDecoder().decode(PKIIdentity.self, from: data) {
                return identity
            }
        }
        return nil
    }

    /// The kept identity, or a new one (RSA 4096 takes a second or more: call it off the main actor).
    public static func loadOrMake(_ keychain: any PeopleKeychain, label: String, synchronise: Bool = true,
                                  rsaBits: Int = 4096) throws -> PKIIdentity {
        if let kept = load(keychain) { return kept }
        let made = try PKI.generate(label: label, rsaBits: rsaBits)
        // The default date encoding is exact; ISO 8601 would drop the fraction of a second and change the identity.
        guard let data = try? JSONEncoder().encode(made),
              keychain.set(account, data, synchronise ? .synchronised : .thisDeviceOnly) else { throw SecretsStore.Failure.keychainRefused }
        return made
    }
}

/// What a screen needs of the people layer, in one observable place: the person's card, contacts, inbox and
/// secrets, and the actions on them. Both apps' screens sit on this; nothing here draws anything.
@MainActor
@Observable
public final class PeopleHub {
    public let identity: PKIIdentity
    public private(set) var name: String
    public let secrets: SecretsStore
    public let book: ContactBook
    public let store: MessageStore
    public let client: LaneClient

    public private(set) var contacts: [Contact] = []
    public private(set) var messages: [ReceivedMessage] = []
    public private(set) var secretList: [KeptSecret] = []
    public private(set) var inbox: InboxKeys?
    public private(set) var lastCheck: Date?
    public private(set) var checking = false
    /// The last problem, in words, for a line on the screen.
    public private(set) var problem: String?

    @ObservationIgnored private var schedule = InboxSchedule()
    @ObservationIgnored private var poller: Task<Void, Never>?

    /// `folder` holds `contacts.json` and `messages.json`.
    public init(identity: PKIIdentity, name: String, folder: URL?, secrets: SecretsStore, client: LaneClient = LaneClient()) {
        self.identity = identity
        self.name = name
        self.secrets = secrets
        self.client = client
        self.book = ContactBook(file: folder?.appendingPathComponent("contacts.json"))
        self.store = MessageStore(file: folder?.appendingPathComponent("messages.json"))
        reload()
    }

    public func reload() {
        contacts = book.all
        messages = store.all
        secretList = secrets.all
        inbox = secrets.inbox
    }

    public func rename(_ newName: String) { name = newName }

    // MARK: You

    /// This person's card: with the inbox once there is one.
    public var myCard: ContactCard? { try? ContactCard.make(name: name, identity: identity, inbox: inbox?.address) }
    public var myCardText: String? { try? myCard?.text() }
    public var myCardLink: String? { try? myCard?.link() }
    public var hasAccessKey: Bool { secrets.accessKey(for: InboxAddress.defaultServer) != nil }

    // MARK: Contacts

    /// Adds the card in `text` (a scan, a picture's code, a pasted link or message).
    @discardableResult
    public func addContact(from text: String, met: HowMet) throws -> ContactBook.Added {
        let added = try book.add(try ContactCard.parse(text), met: met, myFingerprint: identity.bundle.fingerprint)
        reload()
        return added
    }

    public func contact(_ id: String) -> Contact? { book.contact(id) }
    public func removeContact(_ id: String) { book.remove(id); reload() }
    public func renameContact(_ id: String, to nickname: String?) { book.rename(id, to: nickname); reload() }
    public func markVerified(_ id: String) { book.markVerified(id); reload() }

    /// The name to show for a message's sender.
    public func senderName(_ message: ReceivedMessage) -> String {
        if let signer = message.signer, let contact = book.contact(signingFingerprint: signer) { return contact.name }
        if let card = message.message?.card.flatMap({ try? ContactCard.parse($0) }) { return card.name + " (not a contact)" }
        return message.signer.map { "Unknown key \($0)" } ?? "Unknown sender"
    }

    // MARK: Sending

    public enum SendFailure: Error, Equatable, LocalizedError {
        case noInbox(String)
        public var errorDescription: String? {
            switch self {
            case .noInbox(let name): "\(name) has no inbox yet: they need to send you their card with one."
            }
        }
    }

    private func send(_ message: PeopleMessage, to contact: Contact) async throws {
        guard let address = contact.card.inbox else { throw SendFailure.noInbox(contact.name) }
        try await client.write(try message.lanePayload(to: contact.card.bundle, from: identity), to: address)
    }

    private func outgoing(_ kind: MessageKind, to contact: Contact, text: String? = nil, secret: SharedSecret? = nil,
                          voiceNote: VoiceNoteReference? = nil, vault: VaultInvitation? = nil, withCard: Bool = false) -> PeopleMessage {
        PeopleMessage(kind: kind, from: identity.bundle.signingFingerprint, to: contact.id,
                      card: withCard ? myCardText : nil, text: text, secret: secret, voiceNote: voiceNote, vault: vault)
    }

    public func sendText(_ text: String, to contact: Contact) async throws {
        try await send(outgoing(.text, to: contact, text: text), to: contact)
    }

    /// Sends this person's card, so that the contact can write back (adding is two-way).
    public func sendMyCard(to contact: Contact) async throws {
        try await send(outgoing(.card, to: contact, withCard: true), to: contact)
        book.recordCardSent(to: contact.id)
        reload()
    }

    public func sendVoiceNote(_ note: VoiceNoteReference, to contact: Contact) async throws {
        try await send(outgoing(.voiceNote, to: contact, voiceNote: note), to: contact)
    }

    public func sendVault(_ invitation: VaultInvitation, to contact: Contact) async throws {
        try await send(outgoing(.vaultInvitation, to: contact, vault: invitation), to: contact)
    }

    /// Gives a kept secret to a contact and remembers that they hold this version.
    public func shareSecret(_ id: String, with contact: Contact) async throws {
        try await send(outgoing(.secret, to: contact, secret: try secrets.outgoing(id)), to: contact)
        try secrets.recordShared(id, with: contact)
        reload()
    }

    // MARK: Secrets

    @discardableResult
    public func addSecret(kind: SecretKind, name: String, value: String, server: String? = nil, note: String? = nil) throws -> KeptSecret {
        let kept = try secrets.add(kind: kind, name: name, value: value, server: server, note: note)
        reload()
        return kept
    }

    public func changeSecret(_ id: String, value: String) throws {
        try secrets.change(id, value: value)
        reload()
    }

    public func removeSecret(_ id: String) { secrets.remove(id); reload() }

    /// Takes a secret that arrived in a message into the store: one tap, never automatic.
    @discardableResult
    public func keepSecret(from message: ReceivedMessage) throws -> KeptSecret? {
        guard let shared = message.message?.secret, let signer = message.signer,
              message.trust == .contact || message.trust == .cardInside else { return nil }
        let sender = book.contact(signingFingerprint: signer)
        let holder = SecretHolder(fingerprint: sender?.id ?? signer, name: sender?.name ?? senderName(message),
                                  at: Date(), version: shared.version)
        let kept = try secrets.receive(shared, from: holder)
        reload()
        return kept
    }

    public func setSynchronise(_ on: Bool) { secrets.setSynchronise(on); reload() }

    // MARK: The inbox

    public func markRead(_ id: String) { store.markRead(id); reload() }
    public func removeMessage(_ id: String) { store.remove(id); reload() }
    public var unread: Int { messages.filter { $0.readAt == nil }.count }

    /// Makes this person's inbox with the access key in the store. Needs a commit signer for the new vault.
    public func makeInbox(signer: any VaultCommitSigner, server: String = InboxAddress.defaultServer) async throws {
        guard inbox == nil else { return }
        guard let accessKey = secrets.accessKey(for: server), let url = URL(string: server) else {
            throw FirstContact.Failure.noAccessKey
        }
        let keys = try await InboxMaker(server: url, client: client).make(server: server, accessToken: accessKey, signer: signer)
        try secrets.saveInbox(keys)
        reload()
    }

    /// Checks now. New cards from contacts update them; nothing else is acted on without the person.
    @discardableResult
    public func checkNow() async -> Int {
        guard let inbox else {
            // Nothing to check until there is an inbox; noted, so that the schedule waits rather than spins.
            schedule.note(.checked(newMessages: 0), at: Date())
            return 0
        }
        guard !checking else { return 0 }
        checking = true
        defer { checking = false }
        do {
            let new = try await InboxCheck(client: client).run(keys: inbox, me: identity, contacts: book.bundles, store: store)
            for message in new { book.absorbCard(from: message, myFingerprint: identity.bundle.fingerprint) }
            problem = nil
            lastCheck = Date()
            schedule.note(.checked(newMessages: new.count), at: Date())
            reload()
            return new.count
        } catch {
            problem = error.localizedDescription
            schedule.note(.checked(newMessages: 0), at: Date())
            return 0
        }
    }

    // MARK: First contact

    /// The inviter's side: the access key in the store, sealed to a newcomer's card. `inPerson` leaves this
    /// person's card out, so the code fits a QR code (the newcomer has scanned it already).
    public func invite(newcomerCard text: String, inPerson: Bool, met: HowMet) throws -> String {
        let newcomer = try ContactCard.parse(text)
        try book.add(newcomer, met: met, myFingerprint: identity.bundle.fingerprint)
        guard let kept = secretList.first(where: { $0.kind == .accessKey }) ?? secrets.all.first(where: { $0.kind == .accessKey }) else {
            throw FirstContact.Failure.noAccessKey
        }
        let sealed = try FirstContact.invitation(accessKey: try secrets.outgoing(kept.id), to: newcomer, from: identity,
                                                 myCard: inPerson ? nil : myCard)
        if let contact = book.contact(newcomer.fingerprint) { try secrets.recordShared(kept.id, with: contact) }
        reload()
        return sealed
    }

    /// The newcomer's side: opens an invitation and does the rest (keep the key, add the inviter, make the inbox,
    /// send the full card).
    public func accept(invitation text: String, signer: any VaultCommitSigner, met: HowMet) async throws {
        let invitation = try FirstContact.open(text, me: identity, contacts: book.bundles)
        let server = invitation.accessKey.server ?? InboxAddress.defaultServer
        guard let url = URL(string: server) else { throw FirstContact.Failure.noAccessKey }
        _ = try await FirstContact.accept(invitation, name: name, me: identity, secrets: secrets, contacts: book,
                                          maker: InboxMaker(server: url, client: client), client: client, signer: signer, how: met)
        reload()
    }

    // MARK: When to check

    /// Tell the hub when the app comes to the front, goes to the back, or the person does something.
    public func note(_ event: InboxSchedule.Event) {
        schedule.note(event, at: Date())
        if case .background = event { stopPolling() } else if poller == nil, schedule.inForeground { startPolling() }
    }

    private func startPolling() {
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                guard let next = self.schedule.nextCheck(at: now) else { return }
                let wait = max(0, next.timeIntervalSince(now))
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(min(wait, 60) * 1_000_000_000)) }
                if Task.isCancelled { return }
                if self.schedule.shouldCheck(at: Date()) { await self.checkNow() }
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }
}
