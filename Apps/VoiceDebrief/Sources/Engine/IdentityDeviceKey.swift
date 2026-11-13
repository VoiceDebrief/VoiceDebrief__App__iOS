import CryptoKit
import Foundation
import Security
import SGitVault

/// This device's key pair: which device, or which install of the app, did something. It never leaves the device.
///
/// - In the Secure Enclave where there is one: the private key is made inside the chip and cannot be read out.
///   What the Keychain holds (this device only) is a handle that only this chip can use.
/// - Otherwise (the simulator) a software P-256 key, in the Keychain marked for this device only.
/// - It is meant to be lost with the device or the app. Keychain items survive deleting an app, so the first
///   use after a reinstall wipes the old key: a marker in `UserDefaults`, which a reinstall does clear, tells
///   the two apart.
///
/// It signs without asking for Face ID, so that a commit can be made when a recording finishes. Carried over
/// from `PTVaultUI/VaultDeviceSigner.swift` in `PrompTugal__App__iOS`, without the biometric access control
/// and with the wipe on reinstall.
struct IdentityDeviceSigner: VaultCommitSigner, Equatable, @unchecked Sendable {
    let keyId: String
    let publicKeyPEM: String
    let secureEnclave: Bool
    let createdAt: Date
    private let handle: Data

    fileprivate init(keyId: String, publicKeyPEM: String, secureEnclave: Bool, createdAt: Date, handle: Data) {
        self.keyId = keyId
        self.publicKeyPEM = publicKeyPEM
        self.secureEnclave = secureEnclave
        self.createdAt = createdAt
        self.handle = handle
    }

    /// Raw r‖s (64 bytes) over `data`, hashed with SHA-256: what sgit stores for a commit.
    func sign(_ data: Data) throws -> Data {
        if secureEnclave {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle).signature(for: data).rawRepresentation
        }
        return try P256.Signing.PrivateKey(rawRepresentation: handle).signature(for: data).rawRepresentation
    }

    var fingerprint: String {
        (try? PKI.publicDER(publicKeyPEM)).map { LaneCrypto.fingerprint(spki: $0) } ?? ""
    }

    /// The word the vouching statement uses for where the key is kept.
    var kept: String { secureEnclave ? "secure-enclave" : "keychain-this-device" }

    var keptInWords: String {
        secureEnclave ? "In this device's Secure Enclave. It cannot be copied out." : "In the Keychain, for this device only (no Secure Enclave here)."
    }

    var asVouchDevice: IdentityVouch.Device {
        IdentityVouch.Device(publicKeyPEM: publicKeyPEM, keyId: keyId, name: IdentityDeviceKey.deviceName, kept: kept)
    }
}

enum IdentityDeviceKey {
    static let itemName = "device-key"
    /// What else belongs to this install's key and goes with it: a sign-in request in progress, and the
    /// delegation a person in the register gave this key.
    static let requestItem = "pki-request"
    static let connectionItem = "pki-connection"
    static let installMarker = "vd.identity.install"

    private struct Stored: Codable {
        var keyId: String
        var handle: Data
        var secureEnclave: Bool
        var createdAt: Date
    }

    /// "iPhone", "iPad" or "Mac": the kind of device, which is all an app is told. Not a name the person chose.
    static var deviceName: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if machine.hasPrefix("iPad") { return "iPad" }
        if machine.hasPrefix("iPhone") { return "iPhone" }
        return machine.isEmpty ? "device" : machine
        #endif
    }

    /// Removes a device key left by an earlier install, and what was bound to it. True when this was the first use since the app was installed.
    @discardableResult
    static func wipeIfReinstalled(store: any IdentityKeyStore, defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: installMarker) == nil else { return false }
        for name in [itemName, requestItem, connectionItem] { store.set(name, nil, .thisDeviceOnly) }
        defaults.set(UUID().uuidString, forKey: installMarker)
        return true
    }

    private static func signer(_ stored: Stored) throws -> IdentityDeviceSigner {
        let spki: Data
        if stored.secureEnclave {
            spki = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored.handle).publicKey.derRepresentation
        } else {
            spki = try P256.Signing.PrivateKey(rawRepresentation: stored.handle).publicKey.derRepresentation
        }
        return IdentityDeviceSigner(keyId: stored.keyId, publicKeyPEM: PKI.pem(spki, label: "PUBLIC KEY"),
                                    secureEnclave: stored.secureEnclave, createdAt: stored.createdAt, handle: stored.handle)
    }

    /// The key this install already has, if it has one. Never makes one.
    static func existing(store: any IdentityKeyStore, defaults: UserDefaults) -> IdentityDeviceSigner? {
        wipeIfReinstalled(store: store, defaults: defaults)
        guard let data = store.get(itemName, .thisDeviceOnly), let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return try? signer(stored)
    }

    /// This install's key, made on first use.
    /// - Parameter useSecureEnclave: whether to ask the chip for the key. Tests pass false.
    static func current(store: any IdentityKeyStore, defaults: UserDefaults, useSecureEnclave: Bool = SecureEnclave.isAvailable,
                        now: Date = Date()) throws -> IdentityDeviceSigner {
        if let have = existing(store: store, defaults: defaults) { return have }
        var stored: Stored?
        if useSecureEnclave {
            var error: Unmanaged<CFError>?
            if let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [.privateKeyUsage], &error),
               let key = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: access) {
                stored = Stored(keyId: VaultCommitBuilder.newKeyId(), handle: key.dataRepresentation, secureEnclave: true, createdAt: now)
            }
        }
        let made = stored ?? Stored(keyId: VaultCommitBuilder.newKeyId(), handle: P256.Signing.PrivateKey().rawRepresentation,
                                    secureEnclave: false, createdAt: now)
        let status = store.set(itemName, try JSONEncoder().encode(made), .thisDeviceOnly)
        guard status == errSecSuccess else { throw PKIError.key("the Keychain refused the device key (status \(status))") }
        return try signer(made)
    }

    /// Forgets this device's key. What it signed can still be checked: the public half is in the vault.
    static func delete(store: any IdentityKeyStore) {
        store.set(itemName, nil, .thisDeviceOnly)
    }
}
