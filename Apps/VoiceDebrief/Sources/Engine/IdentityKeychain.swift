import Foundation
import Security

/// The two homes a key of the identity can have (see the article "Where each key lives").
enum IdentityKeyHome: String, Sendable {
    /// iCloud Keychain: carried to the person's other devices, encrypted so that Apple cannot read it.
    /// A synchronised item cannot also demand Face ID.
    case synchronised
    /// The Keychain of this device only: in no backup that leaves it, never carried anywhere.
    case thisDeviceOnly
}

/// Where the identity keeps what is secret. The Keychain on a device; memory in tests.
/// Its own small type, because `SecretStore` (the vaults') is being given the same distinction for
/// issue 017 by another session: when that lands, this can become a thin layer over it.
protocol IdentityKeyStore: Sendable {
    func get(_ name: String, _ home: IdentityKeyHome) -> Data?
    /// Writes, or removes when `value` is nil. Returns the Keychain's status: 0 is success.
    @discardableResult func set(_ name: String, _ value: Data?, _ home: IdentityKeyHome) -> OSStatus
}

/// Generic passwords in the Keychain, under a service of their own.
struct IdentityKeychain: IdentityKeyStore {
    let service: String

    init(service: String = "ai.voicedebrief.app.identity") {
        self.service = service
    }

    private func query(_ name: String, _ home: IdentityKeyHome) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecAttrSynchronizable as String: home == .synchronised,
         kSecUseDataProtectionKeychain as String: true]
    }

    func get(_ name: String, _ home: IdentityKeyHome) -> Data? {
        var q = query(name, home)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    func set(_ name: String, _ value: Data?, _ home: IdentityKeyHome) -> OSStatus {
        let removed = SecItemDelete(query(name, home) as CFDictionary)
        guard let value else { return removed == errSecItemNotFound ? errSecSuccess : removed }
        var q = query(name, home)
        q[kSecValueData as String] = value
        // After first unlock, so a commit can be signed while the screen is locked. Only the device-only
        // class keeps the item out of iCloud Keychain and out of backups that leave the device.
        q[kSecAttrAccessible as String] = home == .synchronised ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil)
    }
}

/// For tests: nothing leaves the process. The two homes are kept apart, as the Keychain keeps them.
final class IdentityMemoryKeyStore: IdentityKeyStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func get(_ name: String, _ home: IdentityKeyHome) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values["\(home.rawValue)/\(name)"]
    }

    @discardableResult
    func set(_ name: String, _ value: Data?, _ home: IdentityKeyHome) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        values["\(home.rawValue)/\(name)"] = value
        return errSecSuccess
    }

    /// What a reinstall leaves behind: the Keychain's items survive, so a copy of this store is what the new install finds.
    func names(_ home: IdentityKeyHome) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values.keys.filter { $0.hasPrefix(home.rawValue + "/") }.map { String($0.dropFirst(home.rawValue.count + 1)) }.sorted()
    }
}
