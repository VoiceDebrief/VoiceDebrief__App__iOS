import Foundation
import Security

// Copied from Apps/VoiceDebrief/Sources/Engine/SecretStore.swift (v0.1.8), with this app's own
// Keychain service. Shared app code moves into a package later; until then keep the two alike.

/// Where the app keeps what must not be readable by anything else: vault keys, the access token,
/// the key that signs commits. The Keychain on a device; memory in tests.
protocol SecretStore: Sendable {
    func get(_ name: String) -> Data?
    func set(_ name: String, _ value: Data?)
}

/// Generic passwords in the Keychain, readable only on this device and only after it has been
/// unlocked once since it started. They are not in any backup that leaves the device.
struct KeychainStore: SecretStore {
    let service: String

    init(service: String = "ai.sgit.app.vaults") {
        self.service = service
    }

    private func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    func get(_ name: String) -> Data? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func set(_ name: String, _ value: Data?) {
        SecItemDelete(query(name) as CFDictionary)
        guard let value else { return }
        var q = query(name)
        q[kSecValueData as String] = value
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// For tests: nothing leaves the process.
final class MemoryStore: SecretStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func get(_ name: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[name]
    }

    func set(_ name: String, _ value: Data?) {
        lock.lock(); defer { lock.unlock() }
        values[name] = value
    }
}
