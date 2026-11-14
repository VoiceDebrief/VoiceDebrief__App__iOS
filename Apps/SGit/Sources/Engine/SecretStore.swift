import Foundation
import Security

// After Apps/VoiceDebrief/Sources/Engine/SecretStore.swift (its two homes, issue 017 there), with this
// app's own Keychain service.

/// The two homes a secret can have.
enum SecretHome: String, Sendable, CaseIterable {
    /// iCloud Keychain: carried to the person's other devices signed in to the same Apple account,
    /// end-to-end encrypted by Apple's design so that Apple cannot read it.
    case synchronised
    /// The Keychain of this device only: in no backup that leaves it, never carried anywhere.
    case thisDeviceOnly
}

/// Where the app keeps what must not be readable by anything else: vault keys, the access key, the key
/// that signs commits. The Keychain on a device; memory in tests. The two homes are separate: the same
/// name can hold a different value in each.
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

/// Generic passwords in the Keychain. An item on this device only is readable after the device has been
/// unlocked once since it started and is in no backup that leaves the device. A synchronised item is the
/// same without "this device only": iCloud Keychain carries it.
struct KeychainStore: SecretStore {
    let service: String

    init(service: String = "ai.sgit.vaults.app.vaults") {
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
