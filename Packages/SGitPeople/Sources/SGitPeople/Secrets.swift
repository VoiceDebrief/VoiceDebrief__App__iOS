import Foundation
import LocalAuthentication
import Security

/// The kinds of secret the store keeps.
public enum SecretKind: String, Codable, CaseIterable, Sendable {
    /// A vault server's access key: what a person needs to create vaults, an inbox among them.
    case accessKey = "access-key"
    case vaultKey = "vault-key"
    case password
    case apiToken = "api-token"
    case note

    public var words: String {
        switch self {
        case .accessKey: "Server access key"
        case .vaultKey: "Vault key"
        case .password: "Password"
        case .apiToken: "API token"
        case .note: "Secret note"
        }
    }
}

/// Someone a secret was given to, or received from.
public struct SecretHolder: Codable, Equatable, Sendable {
    /// Their encryption fingerprint (the contact's id).
    public var fingerprint: String
    public var name: String
    public var at: Date
    /// The version they were given.
    public var version: Int

    public init(fingerprint: String, name: String, at: Date, version: Int) {
        self.fingerprint = fingerprint
        self.name = name
        self.at = at
        self.version = version
    }
}

/// What the store knows about a secret, without its value: safe to list without Face ID.
public struct KeptSecret: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: SecretKind
    public var name: String
    public var server: String?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Starts at 1; each change of value adds one.
    public var version: Int
    /// Who sent it here, and the sender's own id for it (so that a later version replaces this one).
    public var receivedFrom: SecretHolder?
    public var senderSecretId: String?
    /// Who it was given to, latest gift per person.
    public var heldBy: [SecretHolder]

    public init(id: String, kind: SecretKind, name: String, server: String? = nil, note: String? = nil, createdAt: Date,
                updatedAt: Date, version: Int = 1, receivedFrom: SecretHolder? = nil, senderSecretId: String? = nil,
                heldBy: [SecretHolder] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.server = server
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.receivedFrom = receivedFrom
        self.senderSecretId = senderSecretId
        self.heldBy = heldBy
    }

    /// The people holding an older value: after a change, the ones to send the new value to.
    public var holdersOfAnOlderVersion: [SecretHolder] { heldBy.filter { $0.version < version } }
}

/// The two places a Keychain item can live.
public enum KeychainHome: String, Codable, CaseIterable, Sendable {
    /// iCloud Keychain: carried to the person's other devices, end-to-end encrypted. Cannot demand Face ID itself.
    case synchronised
    /// This device only, in no backup that leaves it.
    case thisDeviceOnly
}

/// Generic-password storage: the Keychain on a device, memory in tests.
public protocol PeopleKeychain: Sendable {
    func get(_ account: String, _ home: KeychainHome) -> Data?
    /// Writes, or removes when `value` is nil. Returns whether it was taken.
    @discardableResult func set(_ account: String, _ value: Data?, _ home: KeychainHome) -> Bool
    func accounts(_ home: KeychainHome) -> [String]
}

/// The Keychain. Each app passes its own service name.
public struct LiveKeychain: PeopleKeychain {
    public let service: String

    public init(service: String) { self.service = service }

    private func query(_ account: String?, _ home: KeychainHome) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrSynchronizable as String: home == .synchronised,
                                kSecUseDataProtectionKeychain as String: true]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    public func get(_ account: String, _ home: KeychainHome) -> Data? {
        var q = query(account, home)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    public func set(_ account: String, _ value: Data?, _ home: KeychainHome) -> Bool {
        let removed = SecItemDelete(query(account, home) as CFDictionary)
        guard let value else { return removed == errSecSuccess || removed == errSecItemNotFound }
        var q = query(account, home)
        q[kSecValueData as String] = value
        q[kSecAttrAccessible as String] = home == .synchronised ? kSecAttrAccessibleAfterFirstUnlock
                                                                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public func accounts(_ home: KeychainHome) -> [String] {
        var q = query(nil, home)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

/// What iCloud Keychain is to a test: shared by every `MemoryKeychain` given it.
public final class MemoryCloudKeychain: @unchecked Sendable {
    fileprivate var values: [String: Data] = [:]
    fileprivate let lock = NSLock()
    public init() {}
}

/// For tests: two keychains given one cloud are two devices on one Apple account.
public final class MemoryKeychain: PeopleKeychain, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public let cloud: MemoryCloudKeychain

    public init(cloud: MemoryCloudKeychain = MemoryCloudKeychain()) { self.cloud = cloud }

    public func get(_ account: String, _ home: KeychainHome) -> Data? {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            return cloud.values[account]
        }
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    @discardableResult
    public func set(_ account: String, _ value: Data?, _ home: KeychainHome) -> Bool {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            cloud.values[account] = value
            return true
        }
        lock.lock(); defer { lock.unlock() }
        values[account] = value
        return true
    }

    public func accounts(_ home: KeychainHome) -> [String] {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            return Array(cloud.values.keys)
        }
        lock.lock(); defer { lock.unlock() }
        return Array(values.keys)
    }
}

/// The secrets manager's store. Each secret is two Keychain items: `meta.<id>` (what it is, who holds it) and
/// `value.<id>` (the secret). Both live in iCloud Keychain unless `synchronise` is off, and then on this device
/// only. Reading a value is the caller's to gate: `SecretsStore.unlock` asks for Face ID or the passcode.
/// (A synchronised Keychain item cannot itself demand Face ID, so the gate is the app's.)
public final class SecretsStore: @unchecked Sendable {
    public enum Failure: Error, Equatable, LocalizedError {
        case notKept
        case emptyValue
        case keychainRefused

        public var errorDescription: String? {
            switch self {
            case .notKept: "That secret is not in the store."
            case .emptyValue: "A secret needs a value."
            case .keychainRefused: "The Keychain did not take the secret."
            }
        }
    }

    public let keychain: any PeopleKeychain
    private let lock = NSLock()
    private var synchroniseFlag: Bool

    public init(keychain: any PeopleKeychain, synchronise: Bool = true) {
        self.keychain = keychain
        self.synchroniseFlag = synchronise
    }

    public var synchronise: Bool {
        lock.lock(); defer { lock.unlock() }
        return synchroniseFlag
    }

    private var home: KeychainHome { synchronise ? .synchronised : .thisDeviceOnly }

    static func metaAccount(_ id: String) -> String { "meta.\(id)" }
    static func valueAccount(_ id: String) -> String { "value.\(id)" }

    /// Every secret, newest change first. Values are not read.
    public var all: [KeptSecret] {
        let ids = keychain.accounts(home).filter { $0.hasPrefix("meta.") }.map { String($0.dropFirst(5)) }
        return ids.compactMap { meta($0) }.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }

    public func meta(_ id: String) -> KeptSecret? {
        keychain.get(Self.metaAccount(id), home).flatMap { try? JSONDecoder.people.decode(KeptSecret.self, from: $0) }
    }

    /// The value. Ask `unlock` first when a person is about to see it.
    public func value(_ id: String) -> String? {
        keychain.get(Self.valueAccount(id), home).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func write(_ secret: KeptSecret, value: String?) throws {
        guard let meta = try? JSONEncoder.people.encode(secret) else { throw Failure.keychainRefused }
        if let value {
            guard keychain.set(Self.valueAccount(secret.id), Data(value.utf8), home) else { throw Failure.keychainRefused }
        }
        guard keychain.set(Self.metaAccount(secret.id), meta, home) else { throw Failure.keychainRefused }
    }

    @discardableResult
    public func add(kind: SecretKind, name: String, value: String, server: String? = nil, note: String? = nil,
                    at date: Date = Date()) throws -> KeptSecret {
        guard !value.isEmpty else { throw Failure.emptyValue }
        let secret = KeptSecret(id: PeopleMessage.newId(), kind: kind, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                server: server, note: note, createdAt: date, updatedAt: date)
        try write(secret, value: value)
        return secret
    }

    /// A new value: the version goes up, and the people holding the old one are listed by `holdersOfAnOlderVersion`.
    @discardableResult
    public func change(_ id: String, value: String, at date: Date = Date()) throws -> KeptSecret {
        guard var secret = meta(id) else { throw Failure.notKept }
        guard !value.isEmpty else { throw Failure.emptyValue }
        secret.version += 1
        secret.updatedAt = date
        try write(secret, value: value)
        return secret
    }

    public func rename(_ id: String, to name: String, note: String?) throws {
        guard var secret = meta(id) else { throw Failure.notKept }
        secret.name = name
        secret.note = note
        try write(secret, value: nil)
    }

    /// Remembers that `contact` was given the current version.
    @discardableResult
    public func recordShared(_ id: String, with contact: Contact, at date: Date = Date()) throws -> KeptSecret {
        guard var secret = meta(id) else { throw Failure.notKept }
        secret.heldBy.removeAll { $0.fingerprint == contact.id }
        secret.heldBy.append(SecretHolder(fingerprint: contact.id, name: contact.name, at: date, version: secret.version))
        try write(secret, value: nil)
        return secret
    }

    /// The message that gives this secret to someone.
    public func outgoing(_ id: String) throws -> SharedSecret {
        guard let secret = meta(id), let value = value(id) else { throw Failure.notKept }
        return SharedSecret(id: secret.id, kind: secret.kind, name: secret.name, value: value, server: secret.server,
                            note: secret.note, version: secret.version)
    }

    /// Takes a secret that arrived in a message. One already received from the same sender under the same id
    /// is replaced when the new version is later, and left alone otherwise.
    @discardableResult
    public func receive(_ shared: SharedSecret, from sender: SecretHolder, at date: Date = Date()) throws -> KeptSecret {
        guard !shared.value.isEmpty else { throw Failure.emptyValue }
        if var known = all.first(where: { $0.senderSecretId == shared.id && $0.receivedFrom?.fingerprint == sender.fingerprint }) {
            guard shared.version > (known.receivedFrom?.version ?? 0) else { return known }
            known.receivedFrom = SecretHolder(fingerprint: sender.fingerprint, name: sender.name, at: date, version: shared.version)
            known.version += 1
            known.updatedAt = date
            known.kind = shared.kind
            known.server = shared.server
            try write(known, value: shared.value)
            return known
        }
        let secret = KeptSecret(id: PeopleMessage.newId(), kind: shared.kind, name: shared.name, server: shared.server,
                                note: shared.note, createdAt: date, updatedAt: date,
                                receivedFrom: SecretHolder(fingerprint: sender.fingerprint, name: sender.name, at: date, version: shared.version),
                                senderSecretId: shared.id)
        try write(secret, value: shared.value)
        return secret
    }

    public func remove(_ id: String) {
        for home in KeychainHome.allCases {
            keychain.set(Self.valueAccount(id), nil, home)
            keychain.set(Self.metaAccount(id), nil, home)
        }
    }

    /// The access key for a server, if one is kept: the newest.
    public func accessKey(for server: String) -> String? {
        let wanted = server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let secret = all.first(where: {
            $0.kind == .accessKey && ($0.server?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? wanted) == wanted
        }) else { return nil }
        return value(secret.id)
    }

    /// Turns iCloud Keychain on or off for every secret: each item is written to the new home and then
    /// removed from the old one, so nothing is lost if the move stops half way.
    public func setSynchronise(_ on: Bool) {
        let from: KeychainHome = on ? .thisDeviceOnly : .synchronised
        let to: KeychainHome = on ? .synchronised : .thisDeviceOnly
        lock.lock()
        let changed = synchroniseFlag != on
        synchroniseFlag = on
        lock.unlock()
        guard changed else { return }
        for account in keychain.accounts(from) where account.hasPrefix("meta.") || account.hasPrefix("value.") || account.hasPrefix("inbox.") {
            if let data = keychain.get(account, from), keychain.set(account, data, to) {
                keychain.set(account, nil, from)
            }
        }
    }

    // MARK: This device's inbox

    /// The keys to this person's own inbox, kept like any secret (they read it).
    public func saveInbox(_ keys: InboxKeys) throws {
        guard let data = try? JSONEncoder.people.encode(keys), keychain.set("inbox.keys", data, home) else { throw Failure.keychainRefused }
    }

    public var inbox: InboxKeys? {
        keychain.get("inbox.keys", home).flatMap { try? JSONDecoder.people.decode(InboxKeys.self, from: $0) }
    }

    // MARK: Face ID

    /// Asks for Face ID, Touch ID or the passcode before a value is shown. True when the person passed.
    public static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
