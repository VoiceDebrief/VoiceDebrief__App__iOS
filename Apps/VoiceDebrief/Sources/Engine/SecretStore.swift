import Foundation
import Security

/// The two homes a secret can have (see the article "Where each key lives").
enum SecretHome: String, Sendable, CaseIterable {
    /// iCloud Keychain: carried to the person's other devices signed in to the same Apple account,
    /// encrypted so that Apple cannot read it. A synchronised item cannot also demand Face ID.
    case synchronised
    /// The Keychain of this device only: in no backup that leaves it, never carried anywhere.
    case thisDeviceOnly
}

/// Where the app keeps what must not be readable by anything else: vault keys, server tokens, the
/// key that signs commits. The Keychain on a device; memory in tests. Every secret is kept in one of
/// two homes, and the caller says which. The two homes are separate: the same name can hold a
/// different value in each.
protocol SecretStore: Sendable {
    func get(_ name: String, _ home: SecretHome) -> Data?
    /// Writes, or removes when `value` is nil. Returns whether the store took it.
    @discardableResult func set(_ name: String, _ value: Data?, _ home: SecretHome) -> Bool
    /// The names kept in a home.
    func names(_ home: SecretHome) -> [String]
}

extension SecretStore {
    /// On this device only: what a secret is unless the caller says otherwise.
    func get(_ name: String) -> Data? { get(name, .thisDeviceOnly) }
    func set(_ name: String, _ value: Data?) { set(name, value, .thisDeviceOnly) }
}

/// Generic passwords in the Keychain. An item on this device only is readable after the device has
/// been unlocked once since it started and is in no backup that leaves the device. A synchronised
/// item is the same, without the "this device only": iCloud Keychain carries it.
struct KeychainStore: SecretStore {
    let service: String

    init(service: String = "ai.voicedebrief.app.vaults") {
        self.service = service
    }

    /// The home is always part of the query: a query that does not say finds only device items.
    private func query(_ name: String?, _ home: SecretHome) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrSynchronizable as String: home == .synchronised]
        if let name { q[kSecAttrAccount as String] = name }
        return q
    }

    func get(_ name: String, _ home: SecretHome) -> Data? {
        var q = query(name, home)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    func set(_ name: String, _ value: Data?, _ home: SecretHome) -> Bool {
        let removed = SecItemDelete(query(name, home) as CFDictionary)
        guard let value else { return removed == errSecSuccess || removed == errSecItemNotFound }
        var q = query(name, home)
        q[kSecValueData as String] = value
        q[kSecAttrAccessible as String] = home == .synchronised ? kSecAttrAccessibleAfterFirstUnlock
                                                                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func names(_ home: SecretHome) -> [String] {
        var q = query(nil, home)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

/// What iCloud Keychain is to a test: the synchronised items, shared by every `MemoryStore` given it.
final class MemoryCloud: @unchecked Sendable {
    fileprivate var values: [String: Data] = [:]
    fileprivate let lock = NSLock()
    init() {}
}

/// For tests: nothing leaves the process. Two stores given the same `MemoryCloud` are two devices
/// signed in to one account: they share the synchronised items and nothing else.
final class MemoryStore: SecretStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    let cloud: MemoryCloud

    init(cloud: MemoryCloud = MemoryCloud()) {
        self.cloud = cloud
    }

    func get(_ name: String, _ home: SecretHome) -> Data? {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            return cloud.values[name]
        }
        lock.lock(); defer { lock.unlock() }
        return values[name]
    }

    @discardableResult
    func set(_ name: String, _ value: Data?, _ home: SecretHome) -> Bool {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            cloud.values[name] = value
            return true
        }
        lock.lock(); defer { lock.unlock() }
        values[name] = value
        return true
    }

    func names(_ home: SecretHome) -> [String] {
        if home == .synchronised {
            cloud.lock.lock(); defer { cloud.lock.unlock() }
            return Array(cloud.values.keys)
        }
        lock.lock(); defer { lock.unlock() }
        return Array(values.keys)
    }
}

/// What this device remembers about the secrets it shares.
struct SecretSyncState: Codable, Equatable, Sendable {
    /// Whether shared secrets are kept in iCloud Keychain as well. On unless the person turns it off.
    var on = true
    /// The names this device has seen in iCloud Keychain, or put there.
    var published: Set<String> = []
    /// The names that were in iCloud Keychain and were then removed by another device. This device
    /// keeps its own copy and does not put them back.
    var withdrawn: Set<String> = []
}

/// The secrets that travel: vault keys, the servers and their tokens. One Keychain item each, so two
/// devices adding vaults at the same time do not overwrite each other's list.
///
/// This device always keeps its own copy of each, on this device only, and works from that. With
/// sharing on, each is also kept in iCloud Keychain, and `reconcile` brings the two into line:
///
/// - in iCloud Keychain and not here, or different here: another device made or changed it; taken.
/// - here and never seen in iCloud Keychain: put there (this is also how items from before sharing travel).
/// - here, seen in iCloud Keychain before, and gone from it: another device removed it. This device
///   keeps its copy and does not put it back, so forgetting a vault elsewhere neither takes it away
///   here nor has it reappear there.
///
/// Turning sharing off takes this device's copies of everything first, then removes them from iCloud
/// Keychain. Nothing is ever only in iCloud Keychain once this device has seen it.
final class SharedSecrets {
    static let stateName = "key-sync"

    let store: any SecretStore
    let prefixes: [String]
    private(set) var state: SecretSyncState

    init(store: any SecretStore, prefixes: [String]) {
        self.store = store
        self.prefixes = prefixes
        if let data = store.get(Self.stateName, .thisDeviceOnly), let saved = try? JSONDecoder().decode(SecretSyncState.self, from: data) {
            state = saved
        } else {
            state = SecretSyncState()
        }
    }

    var isOn: Bool { state.on }

    private func saveState() {
        store.set(Self.stateName, try? JSONEncoder().encode(state), .thisDeviceOnly)
    }

    /// Only names with one of the prefixes are shared. Anything else given to `set` stays on this device.
    private func isShared(_ name: String) -> Bool { prefixes.contains { name.hasPrefix($0) } }

    private func ours(_ home: SecretHome) -> Set<String> {
        Set(store.names(home).filter(isShared))
    }

    /// The names of the shared secrets this device holds, with a given prefix.
    func names(_ prefix: String) -> [String] {
        ours(.thisDeviceOnly).filter { $0.hasPrefix(prefix) }.sorted()
    }

    func get(_ name: String) -> Data? { store.get(name, .thisDeviceOnly) }

    /// Keeps a secret, or with nil removes it: here, and in iCloud Keychain when sharing is on. A
    /// secret another device withdrew stays on this device only.
    func set(_ name: String, _ value: Data?) {
        let before = state
        if store.get(name, .thisDeviceOnly) != value { store.set(name, value, .thisDeviceOnly) }
        if !isShared(name) {
            // Not one of the shared kinds: this device only, whatever the switch says.
        } else if value == nil {
            if state.on { store.set(name, nil, .synchronised) }
            state.published.remove(name)
            state.withdrawn.remove(name)
        } else if state.on, !state.withdrawn.contains(name) {
            if store.get(name, .synchronised) == value || store.set(name, value, .synchronised) { state.published.insert(name) }
        }
        if state != before { saveState() }
    }

    /// Where one secret is kept.
    func home(of name: String) -> SecretHome {
        state.on && state.published.contains(name) ? .synchronised : .thisDeviceOnly
    }

    func wasWithdrawn(_ name: String) -> Bool { state.withdrawn.contains(name) }

    /// Brings this device's copies and iCloud Keychain into line. Returns whether anything on this
    /// device changed, so the caller knows to read its lists again.
    @discardableResult
    func reconcile() -> Bool {
        guard state.on else { return false }
        let before = state
        var changedHere = false
        let cloud = ours(.synchronised)
        let here = ours(.thisDeviceOnly)
        for name in cloud {
            guard let value = store.get(name, .synchronised) else { continue }
            if store.get(name, .thisDeviceOnly) != value {
                store.set(name, value, .thisDeviceOnly)
                changedHere = true
            }
            state.published.insert(name)
            state.withdrawn.remove(name)
        }
        for name in here.subtracting(cloud) {
            if state.published.contains(name) {
                state.published.remove(name)
                state.withdrawn.insert(name)
            } else if !state.withdrawn.contains(name), let value = store.get(name, .thisDeviceOnly) {
                if store.set(name, value, .synchronised) { state.published.insert(name) }
            }
        }
        if state != before { saveState() }
        return changedHere
    }

    /// Turns sharing on or off. Off: everything is taken onto this device, then removed from iCloud
    /// Keychain. On: everything this device holds is put there, including what another device withdrew.
    func setOn(_ on: Bool) {
        guard on != state.on else { return }
        if on {
            state.on = true
            state.withdrawn = []
            saveState()
            reconcile()
        } else {
            reconcile()
            for name in ours(.synchronised) { store.set(name, nil, .synchronised) }
            state = SecretSyncState(on: false)
            saveState()
        }
    }
}
