import Foundation
import SGitVault

/// A message that arrived in this device's inbox, as it is kept. A message that could not be opened is kept
/// too, with its raw content, so that nothing that arrived is lost.
public struct ReceivedMessage: Codable, Equatable, Identifiable, Sendable {
    /// The lane's file id: unique per arrival.
    public var id: String
    public var receivedAt: Date
    public var message: PeopleMessage?
    public var trust: SenderTrust?
    public var signer: String?
    /// Why it could not be opened.
    public var problem: String?
    /// The stored content, kept only when it could not be opened.
    public var raw: String?
    public var readAt: Date?

    public init(id: String, receivedAt: Date, message: PeopleMessage? = nil, trust: SenderTrust? = nil, signer: String? = nil,
                problem: String? = nil, raw: String? = nil, readAt: Date? = nil) {
        self.id = id
        self.receivedAt = receivedAt
        self.message = message
        self.trust = trust
        self.signer = signer
        self.problem = problem
        self.raw = raw
        self.readAt = readAt
    }
}

/// The messages on this device, in a JSON file, newest first.
public final class MessageStore: @unchecked Sendable {
    private let file: URL?
    private let lock = NSLock()
    private var messages: [ReceivedMessage]

    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder.people.decode([ReceivedMessage].self, from: data) {
            messages = stored
        } else {
            messages = []
        }
    }

    public var all: [ReceivedMessage] {
        lock.lock(); defer { lock.unlock() }
        return messages.sorted { ($0.receivedAt, $0.id) > ($1.receivedAt, $1.id) }
    }

    public var unread: Int {
        lock.lock(); defer { lock.unlock() }
        return messages.filter { $0.readAt == nil }.count
    }

    public func contains(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return messages.contains { $0.id == id }
    }

    /// Adds what is not already kept, and writes the file before returning: only then may the lane forget them.
    public func add(_ new: [ReceivedMessage]) throws {
        lock.lock()
        for message in new where !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        let snapshot = messages
        lock.unlock()
        try save(snapshot)
    }

    public func markRead(_ id: String, at date: Date = Date()) {
        lock.lock()
        if let index = messages.firstIndex(where: { $0.id == id }), messages[index].readAt == nil { messages[index].readAt = date }
        let snapshot = messages
        lock.unlock()
        try? save(snapshot)
    }

    public func remove(_ id: String) {
        lock.lock()
        messages.removeAll { $0.id == id }
        let snapshot = messages
        lock.unlock()
        try? save(snapshot)
    }

    private func save(_ snapshot: [ReceivedMessage]) throws {
        guard let file else { return }
        try PeopleFiles.write(try JSONEncoder.people.encode(snapshot), to: file)
    }
}

/// One check of one's own inbox: list (one call, without content), and only when something is waiting,
/// fetch it, open each message, keep it on the device, and then mark it processed on the server.
/// A message is marked processed only after the file that keeps it has been written.
public struct InboxCheck: Sendable {
    public let client: LaneClient

    public init(client: LaneClient = LaneClient()) { self.client = client }

    /// Opens one lane entry's content.
    public static func receive(fileId: String, content: String, received: Date, me: PKIIdentity, contacts: [PKIBundle]) -> ReceivedMessage {
        do {
            let opened = try PeopleMessage.open(laneContent: content, me: me, contacts: contacts)
            return ReceivedMessage(id: fileId, receivedAt: received, message: opened.message, trust: opened.trust, signer: opened.signer)
        } catch {
            return ReceivedMessage(id: fileId, receivedAt: received, problem: error.localizedDescription, raw: content)
        }
    }

    /// The messages that were new. Throws only when the server cannot be asked; a message that does not open is kept as such.
    public func run(keys: InboxKeys, me: PKIIdentity, contacts: [PKIBundle], store: MessageStore) async throws -> [ReceivedMessage] {
        let listed = try await client.list(keys, includeContent: false)
        guard !listed.entries.isEmpty else { return [] }
        var new: [ReceivedMessage] = []
        var done: [String: [String]] = [:]
        for (lane, entries) in Dictionary(grouping: listed.entries, by: \.inbox) {
            let known = entries.filter { store.contains($0.fileId) }
            let wanted = entries.filter { !store.contains($0.fileId) }
            done[lane, default: []] += known.map(\.fileId)
            // A few at a time: a message can be megabytes.
            for start in stride(from: 0, to: wanted.count, by: 5) {
                let batch = Array(wanted[start..<min(start + 5, wanted.count)])
                let fetched = try await client.fetch(keys, inbox: lane, fileIds: batch.map(\.fileId))
                let received = Dictionary(batch.map { ($0.fileId, $0.receivedAt) }, uniquingKeysWith: { first, _ in first })
                let opened = fetched.files.map {
                    Self.receive(fileId: $0.fileId, content: $0.content, received: received[$0.fileId] ?? Date(), me: me, contacts: contacts)
                }
                try store.add(opened)
                new += opened
                done[lane, default: []] += opened.map(\.id)
            }
        }
        for (lane, ids) in done where !ids.isEmpty {
            _ = try? await client.markProcessed(keys, inbox: lane, fileIds: ids)
        }
        return new.sorted { $0.receivedAt > $1.receivedAt }
    }
}

/// When to check the inbox. There are no push events, so the app asks: on opening and on coming to the
/// front, every minute while it is being used, and less and less often when it is open but idle, down to
/// once every fifteen minutes. Never in the background. A new message, or the person doing something,
/// brings it back to every minute.
public struct InboxSchedule: Equatable, Sendable {
    public static let whileInUse: TimeInterval = 60
    public static let slowest: TimeInterval = 15 * 60
    /// With no activity for this long, the app counts as idle.
    public static let idleAfter: TimeInterval = 5 * 60

    public enum Event: Equatable, Sendable {
        case opened, foreground, background, activity
        case checked(newMessages: Int)
    }

    public private(set) var inForeground = false
    public private(set) var lastCheck: Date?
    public private(set) var lastActivity: Date?
    /// Checks in a row that found nothing since the app went idle.
    public private(set) var emptyWhileIdle = 0
    public private(set) var dueNow = false

    public init() {}

    public mutating func note(_ event: Event, at now: Date) {
        switch event {
        case .opened, .foreground:
            inForeground = true
            lastActivity = now
            emptyWhileIdle = 0
            dueNow = true
        case .background:
            inForeground = false
            dueNow = false
        case .activity:
            lastActivity = now
            emptyWhileIdle = 0
        case .checked(let count):
            lastCheck = now
            dueNow = false
            if count > 0 {
                lastActivity = now
                emptyWhileIdle = 0
            } else if isIdle(at: now) {
                emptyWhileIdle += 1
            }
        }
    }

    public func isIdle(at now: Date) -> Bool {
        guard let lastActivity else { return true }
        return now.timeIntervalSince(lastActivity) >= Self.idleAfter
    }

    /// The gap after the last check: a minute in use, then doubling with each empty idle check, to the slowest.
    public func interval(at now: Date) -> TimeInterval {
        guard isIdle(at: now) else { return Self.whileInUse }
        return min(Self.whileInUse * pow(2, Double(min(emptyWhileIdle, 10))), Self.slowest)
    }

    /// When the next check should happen; nil in the background.
    public func nextCheck(at now: Date) -> Date? {
        guard inForeground else { return nil }
        if dueNow { return now }
        guard let lastCheck else { return now }
        return lastCheck.addingTimeInterval(interval(at: now))
    }

    public func shouldCheck(at now: Date) -> Bool {
        guard let next = nextCheck(at: now) else { return false }
        return next <= now
    }
}

/// Makes a person's inbox: a new vault of theirs on the server, with an append lane opened on it. This needs
/// the server's access key: the first secret a newcomer is given.
public struct InboxMaker: Sendable {
    public let client: LaneClient
    public let writer: any VaultWriteTransport

    public init(client: LaneClient = LaneClient(), writer: any VaultWriteTransport) {
        self.client = client
        self.writer = writer
    }

    /// On the live server: the vault is created over HTTP at `server`.
    public init(server: URL, client: LaneClient = LaneClient()) {
        self.init(client: client, writer: HTTPVaultTransport(server: server))
    }

    /// Creates the vault (one signed commit, `signer`'s key), then configures its lane. The returned keys are
    /// secret: keep them with `SecretsStore.saveInbox`.
    public func make(server: String, accessToken: String, signer: any VaultCommitSigner) async throws -> InboxKeys {
        let created = try await VaultCreate.create(signer: signer, accessToken: accessToken, writer: writer, message: "An inbox")
        guard let writeKey = created.key.writeKey else { throw VaultError.invalidKey("a new vault has a write key") }
        let writeKeyHex = writeKey.withUnsafeBytes { Data($0) }.hexString
        let address = InboxAddress(server: server, vault: created.key.vaultId, append: LaneClient.randomHex(24))
        let enumKey = LaneClient.randomHex(32)
        try await client.configure(address, writeKeyHex: writeKeyHex, accessToken: accessToken, enumKey: enumKey)
        return InboxKeys(address: address, enumKey: enumKey, vaultKey: created.keyText)
    }
}
