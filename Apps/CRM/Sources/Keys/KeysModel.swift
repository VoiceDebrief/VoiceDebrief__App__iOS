import Foundation
import Observation
import SGitPeople

/// W12, keys by QR: the person's own keys and contact card (SGitPeople, as SGit Vaults has them), and the
/// cards of people they have met. A card holds public keys only: an encryption key (RSA 4096) and a signing
/// key (P-256), signed together. Nothing is made at launch: keys are made when the person asks.
@MainActor
@Observable
final class KeysModel {
    static let peopleService = "ai.sgit.crm.app.people"
    static let secretsService = "ai.sgit.crm.app.people-secrets"

    private(set) var hub: PeopleHub?
    private(set) var making = false
    private(set) var problem: String?

    @ObservationIgnored private let peopleKeychain: any PeopleKeychain
    @ObservationIgnored private let secrets: SecretsStore
    @ObservationIgnored private let folder: URL?
    @ObservationIgnored private let rsaBits: Int

    init(peopleKeychain: any PeopleKeychain = LiveKeychain(service: KeysModel.peopleService),
         secretsKeychain: any PeopleKeychain = LiveKeychain(service: KeysModel.secretsService),
         folder: URL? = KeysModel.defaultFolder, rsaBits: Int = 4096) {
        self.peopleKeychain = peopleKeychain
        self.secrets = SecretsStore(keychain: secretsKeychain)
        self.folder = folder
        self.rsaBits = rsaBits
        if let identity = PeopleIdentity.load(peopleKeychain) { open(identity, name: identity.bundle.label) }
    }

    static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("crm-people")
    }

    var hasIdentity: Bool { hub != nil }

    private func open(_ identity: PKIIdentity, name: String) {
        hub = PeopleHub(identity: identity, name: name, folder: folder, secrets: secrets)
    }

    /// Makes the person's key pair, kept in iCloud Keychain. Takes a second or more.
    func makeIdentity(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !making else { return }
        making = true
        defer { making = false }
        let keychain = peopleKeychain
        let bits = rsaBits
        let made = await Task.detached(priority: .userInitiated) {
            Result { try PeopleIdentity.loadOrMake(keychain, label: trimmed, rsaBits: bits) }
        }.value
        switch made {
        case .success(let identity):
            open(identity, name: trimmed)
            problem = nil
        case .failure(let error):
            problem = error.localizedDescription
        }
    }

    /// Adds the card in a scanned code or a pasted link. `inPerson` when the camera saw it on their screen.
    @discardableResult
    func addCard(_ text: String, inPerson: Bool) throws -> Contact {
        guard let hub else { throw KeysProblem.noKeysYet }
        switch try hub.addContact(from: text, met: inPerson ? .inPerson : .byMessage) {
        case .new(let c), .updated(let c), .unchanged(let c): return c
        }
    }
}

enum KeysProblem: LocalizedError, Equatable {
    case noKeysYet
    var errorDescription: String? { "Make your own keys first: a card is checked against them." }
}

/// A contact's card in the CRM: their key on a person record, as a link with its source.
enum CardLink {
    static let prefix = "sgit:key:"

    static func value(_ contact: Contact) -> String { prefix + contact.card.fingerprint }

    static func source(_ contact: Contact, at: Date) -> Source {
        Source(saidBy: contact.verifiedAt == nil ? "Their contact card, \(contact.met.words)" : "Their contact card, checked face to face",
               at: at.toTheSecond, from: "a scanned SGit contact card", note: "signing key \(contact.card.signingFingerprint)")
    }

    /// The person record for a contact: a new one, or the person named the same with their key added.
    static func person(for contact: Contact, existing people: [Person], by actor: Actor, at rawDate: Date) -> Person {
        let at = rawDate.toTheSecond
        let name = contact.nickname ?? contact.card.name
        let link = Sourced(value(contact), source: source(contact, at: at))
        if var person = people.first(where: { ContactKeys.name($0.name.value) == ContactKeys.name(name) }) {
            if !person.links.contains(where: { $0.value == link.value }) {
                person.links.append(link)
                person.changed = Stamp(at: max(at, person.created.at), by: actor)
            }
            return person
        }
        let stamp = Stamp(at: at, by: actor)
        return Person(id: RecordID.make(), created: stamp, changed: stamp, source: source(contact, at: at),
                      name: Sourced(name), links: [link], tags: ["card"])
    }

    /// Whether a person in the CRM has this contact's key.
    static func has(_ person: Person, _ contact: Contact) -> Bool {
        person.links.contains { $0.value == value(contact) }
    }
}
