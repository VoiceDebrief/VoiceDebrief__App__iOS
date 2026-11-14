import Foundation

/// How a contact's card reached this device. It says how far to trust it, and it is never upgraded by
/// anything but the person: comparing fingerprints face to face sets `verifiedAt`, not this.
public enum HowMet: String, Codable, CaseIterable, Sendable {
    /// Scanned from their screen with the camera: the person and the code were seen together.
    case inPerson = "in-person"
    /// A picture of the code, a link or pasted text: as far as the channel it came by.
    case byMessage = "by-message"
    /// Looked up in a register such as pki.sgit.ai: as far as the register's checks.
    case fromRegister = "from-register"
    /// Arrived in a message in this device's inbox: a new card from someone already known, or the reply that
    /// completes a first contact.
    case throughInbox = "through-inbox"

    public var words: String {
        switch self {
        case .inPerson: "Met in person (scanned)"
        case .byMessage: "Card received by message"
        case .fromRegister: "Found in a register"
        case .throughInbox: "Card arrived in the inbox"
        }
    }
}

/// A person (or an agent) this device knows, by their signed card.
public struct Contact: Codable, Equatable, Identifiable, Sendable {
    /// The encryption key's fingerprint: what sgit calls a key by.
    public var id: String { card.fingerprint }
    public var card: ContactCard
    public var met: HowMet
    public var metAt: Date
    /// A name the owner of this device chose; the card's own name otherwise.
    public var nickname: String?
    /// When the fingerprints were compared face to face (or on a call) and matched.
    public var verifiedAt: Date?
    public var isAgent: Bool
    /// When this device last sent its own card to them, so that they can write back.
    public var sentMyCardAt: Date?
    /// The card this one replaced, when a later card from the same keys changed the name or the inbox.
    public var updatedAt: Date?

    public init(card: ContactCard, met: HowMet, metAt: Date = Date(), nickname: String? = nil, verifiedAt: Date? = nil,
                isAgent: Bool = false, sentMyCardAt: Date? = nil, updatedAt: Date? = nil) {
        self.card = card
        self.met = met
        self.metAt = metAt
        self.nickname = nickname
        self.verifiedAt = verifiedAt
        self.isAgent = isAgent
        self.sentMyCardAt = sentMyCardAt
        self.updatedAt = updatedAt
    }

    public var name: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        return card.name
    }

    /// Whether a message can be sent to them: their card names an inbox.
    public var canReceive: Bool { card.inbox != nil }
}

/// The contacts on this device, in a JSON file. Nothing in it is secret (public keys, names, inbox addresses),
/// but it is private: it says who the owner knows.
public final class ContactBook: @unchecked Sendable {
    public enum Failure: Error, Equatable, LocalizedError {
        /// A card with a known fingerprint but other keys: never taken silently.
        case keysChanged(name: String)
        case isMe

        public var errorDescription: String? {
            switch self {
            case .keysChanged(let name): "This card has the fingerprint of \(name) but different keys. It was not added."
            case .isMe: "This is your own card."
            }
        }
    }

    /// What adding a card did.
    public enum Added: Equatable, Sendable {
        case new(Contact)
        /// A later card from the same keys: the name or the inbox changed.
        case updated(Contact)
        /// The same card, or an older one: nothing changed.
        case unchanged(Contact)

        public var contact: Contact {
            switch self {
            case .new(let c), .updated(let c), .unchanged(let c): c
            }
        }
    }

    private let file: URL?
    private let lock = NSLock()
    private var contacts: [Contact]

    /// `file` nil keeps everything in memory (tests, previews).
    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder.people.decode([Contact].self, from: data) {
            contacts = stored
        } else {
            contacts = []
        }
    }

    /// By name, then fingerprint.
    public var all: [Contact] {
        lock.lock(); defer { lock.unlock() }
        return contacts.sorted { ($0.name.localizedLowercase, $0.id) < ($1.name.localizedLowercase, $1.id) }
    }

    public func contact(_ fingerprint: String) -> Contact? {
        lock.lock(); defer { lock.unlock() }
        return contacts.first { $0.id == fingerprint }
    }

    public func contact(signingFingerprint: String) -> Contact? {
        lock.lock(); defer { lock.unlock() }
        return contacts.first { $0.card.signingFingerprint == signingFingerprint }
    }

    /// The bundles a message's signature can be checked against.
    public var bundles: [PKIBundle] {
        lock.lock(); defer { lock.unlock() }
        return contacts.map(\.card.bundle)
    }

    /// Adds a card that has been checked (`ContactCard.parse` and `fromStatement` check). A card with the same
    /// keys and a later `created_at` replaces the stored one and keeps how they were met; a card with a known
    /// fingerprint and other keys is refused.
    @discardableResult
    public func add(_ card: ContactCard, met: HowMet, at date: Date = Date(), myFingerprint: String? = nil,
                    isAgent: Bool = false) throws -> Added {
        try card.check()
        if card.fingerprint == myFingerprint { throw Failure.isMe }
        lock.lock()
        let result: Added
        if let index = contacts.firstIndex(where: { $0.id == card.fingerprint || $0.card.signingFingerprint == card.signingFingerprint }) {
            let known = contacts[index]
            guard known.card.sameKeys(as: card) else {
                lock.unlock()
                throw Failure.keysChanged(name: known.name)
            }
            if (card.created ?? .distantPast) > (known.card.created ?? .distantPast), card != known.card {
                contacts[index].card = card
                contacts[index].updatedAt = date
                result = .updated(contacts[index])
            } else {
                result = .unchanged(known)
            }
        } else {
            let contact = Contact(card: card, met: met, metAt: date, isAgent: isAgent)
            contacts.append(contact)
            result = .new(contact)
        }
        lock.unlock()
        if case .unchanged = result {} else { save() }
        return result
    }

    public func rename(_ fingerprint: String, to nickname: String?) {
        change(fingerprint) { $0.nickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public func markVerified(_ fingerprint: String, at date: Date? = Date()) {
        change(fingerprint) { $0.verifiedAt = date }
    }

    public func markAgent(_ fingerprint: String, _ isAgent: Bool) {
        change(fingerprint) { $0.isAgent = isAgent }
    }

    public func recordCardSent(to fingerprint: String, at date: Date = Date()) {
        change(fingerprint) { $0.sentMyCardAt = date }
    }

    public func remove(_ fingerprint: String) {
        lock.lock()
        contacts.removeAll { $0.id == fingerprint }
        lock.unlock()
        save()
    }

    private func change(_ fingerprint: String, _ edit: (inout Contact) -> Void) {
        lock.lock()
        guard let index = contacts.firstIndex(where: { $0.id == fingerprint }) else { lock.unlock(); return }
        edit(&contacts[index])
        lock.unlock()
        save()
    }

    private func save() {
        guard let file else { return }
        lock.lock()
        let snapshot = contacts
        lock.unlock()
        guard let data = try? JSONEncoder.people.encode(snapshot) else { return }
        try? PeopleFiles.write(data, to: file)
    }
}

enum PeopleFiles {
    /// Atomically, creating the folder; on iOS readable once the device has been unlocked after it started.
    static func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: [.atomic])
        #endif
    }
}

extension JSONEncoder {
    /// Sorted keys and ISO 8601 dates: files that read the same on every device and diff cleanly.
    static var people: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var people: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
