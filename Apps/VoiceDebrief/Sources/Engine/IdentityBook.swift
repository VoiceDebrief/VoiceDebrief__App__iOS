import Foundation
import Observation
import Security
import SGitVault
import SGitPeople

/// The identity this app holds, and what it does with it.
///
/// - The user's key pair says who the person is: one sgit bundle (RSA-OAEP 4096 and ECDSA P-256), made on
///   first need, its private halves kept in iCloud Keychain so that they reach the person's other devices.
///   Later it moves into a master vault opened by a passkey.
/// - The device's key pair says which install did something. It stays on the device (`IdentityDeviceKey`).
/// - A vouching statement, signed by the user's key, says the device key is theirs (`IdentityVouch`).
/// - Optionally, a delegation from pki.sgit.ai says a person in that register stands behind the device key
///   (`PKIDelegation`). The app works without it.
///
/// Private keys are read from the Keychain when something is signed and are not kept in memory between uses.
@MainActor
@Observable
final class IdentityBook {
    /// The one the screens use. The app is not handed an instance, so that no other file had to change.
    static let shared = IdentityBook()

    static let userItem = "user-identity"
    static let requestItem = IdentityDeviceKey.requestItem
    static let connectionItem = IdentityDeviceKey.connectionItem

    private let store: any IdentityKeyStore
    private let defaults: UserDefaults
    private let fetchIssuer: @Sendable (String) async throws -> PKIBundle

    private(set) var user: PKIBundle?
    private(set) var userCreated: Date?
    private(set) var device: IdentityDeviceSigner?
    private(set) var connection: Connection?
    private(set) var busy: String?
    private(set) var problem: String?
    private(set) var notice: String?

    /// A delegation the app holds, with the issuer's public bundle it was checked against.
    struct Connection: Codable, Equatable, Sendable {
        var delegation: String          // the signed delegation, canonical JSON
        var issuerBundle: PKIBundle
        var receivedAt: Date
    }

    init(store: any IdentityKeyStore = IdentityKeychain(), defaults: UserDefaults = .standard,
         fetchIssuer: @escaping @Sendable (String) async throws -> PKIBundle = IdentityBook.issuerFromRegister) {
        self.store = store
        self.defaults = defaults
        self.fetchIssuer = fetchIssuer
        refresh()
    }

    // MARK: What is kept

    private func storedUser() -> PKIIdentity? {
        guard let data = store.get(Self.userItem, .synchronised) else { return nil }
        return try? JSONDecoder().decode(PKIIdentity.self, from: data)
    }

    /// Reads the Keychain again: an identity made on another device arrives through iCloud Keychain on its own time.
    func refresh() {
        let stored = storedUser()
        user = stored?.bundle
        userCreated = stored?.created
        device = IdentityDeviceKey.existing(store: store, defaults: defaults)
        if let data = store.get(Self.connectionItem, .thisDeviceOnly), let saved = try? JSONDecoder().decode(Connection.self, from: data) {
            connection = saved
        } else {
            connection = nil
        }
    }

    func clearProblem() { problem = nil }
    func report(_ text: String) { problem = text }
    func clearNotice() { notice = nil }

    // MARK: The user's key pair

    /// Makes the user's key pair and keeps it in iCloud Keychain. Does nothing if there is one already.
    /// - Parameter rsaBits: 4096, as sgit makes. Tests pass a smaller size to stay quick.
    func createUser(label: String, rsaBits: Int = 4096) async {
        guard busy == nil else { return }
        problem = nil
        refresh()
        guard user == nil else { notice = "Your identity was already here: it arrived from another device."; return }
        busy = "Making your keys. The large one takes a few seconds."
        defer { busy = nil }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let made = try await Task.detached(priority: .userInitiated) {
                try PKI.generate(label: name.isEmpty ? "VoiceDebrief" : name, rsaBits: rsaBits)
            }.value
            let status = store.set(Self.userItem, try JSONEncoder().encode(made), .synchronised)
            guard status == errSecSuccess else { throw PKIError.key("the Keychain refused it (status \(status))") }
            user = made.bundle
            userCreated = made.created
        } catch {
            problem = "Your identity was not made: \(error.localizedDescription)"
        }
    }

    /// Removes the user's key pair from iCloud Keychain, and so from every device it reached.
    /// Statements it signed can still be checked by anyone who kept its public bundle.
    func forgetUser() {
        store.set(Self.userItem, nil, .synchronised)
        refresh()
    }

    // MARK: The device's key pair

    /// This install's key, made on first use.
    @discardableResult
    func deviceSigner() throws -> IdentityDeviceSigner {
        let signer = try IdentityDeviceKey.current(store: store, defaults: defaults)
        device = signer
        return signer
    }

    func makeDeviceKey() {
        problem = nil
        do { try deviceSigner() } catch { problem = "This device's key was not made: \(error.localizedDescription)" }
    }

    // MARK: Vouching

    /// The files that say, inside a vault, that this device's key is the user's: the signed statement and,
    /// when the app holds one, the delegation from the register.
    func vouchFiles(now: Date = Date()) throws -> [String: Data] {
        guard let identity = storedUser() else { throw PKIError.key("there is no user identity on this device yet") }
        let signer = try deviceSigner()
        let statement = try IdentityVouch.make(for: signer.asVouchDevice, by: identity, at: now)
        var files = [IdentityVouch.path(deviceFingerprint: signer.fingerprint): IdentityVouch.fileData(statement)]
        if let connection, let d = try? PKIJSON(parsing: Data(connection.delegation.utf8)), d["to"] == .string(signer.fingerprint) {
            files[Self.delegationPath(deviceFingerprint: signer.fingerprint)] = Data((connection.delegation + "\n").utf8)
        }
        return files
    }

    static func delegationPath(deviceFingerprint: String) -> String {
        "\(IdentityVouch.folder)/\(deviceFingerprint.replacingOccurrences(of: ":", with: "-")).delegation.json"
    }

    // MARK: Optionally, a person in the register

    /// The key the register is asked to vouch for: this device's signing key, with the user's encryption key
    /// beside it (a key code carries one of each).
    func delegationKey() throws -> PKIBundle {
        guard let user else { throw PKIError.key("make your identity first") }
        let signer = try deviceSigner()
        return PKI.bundle(encryptSPKI: try PKI.publicDER(user.encrypt), signSPKI: try PKI.publicDER(signer.publicKeyPEM),
                          label: "VoiceDebrief on this \(IdentityDeviceKey.deviceName)")
    }

    private struct PendingRequest: Codable {
        var client: String
        var returnAddress: String
        var key: String
        var can: [String]
        var days: Int
        var nonce: String
        var label: String
    }

    /// A new sign-in request, remembered so that only its answer is accepted. Returns the address to open.
    func beginConnection(days: Int = 90) throws -> URL {
        let key = try delegationKey()
        let r = try PKIDelegation.request(for: key, days: days, label: key.label)
        let pending = PendingRequest(client: r.client, returnAddress: r.returnAddress, key: r.key, can: r.can, days: r.days, nonce: r.nonce, label: r.label)
        store.set(Self.requestItem, try JSONEncoder().encode(pending), .thisDeviceOnly)
        guard let url = URL(string: r.url) else { throw PKIError.format("the request does not make an address") }
        return url
    }

    var hasPendingRequest: Bool { store.get(Self.requestItem, .thisDeviceOnly) != nil }

    static func today(_ date: Date = Date()) -> String { IdentityVouch.day(date) }

    /// Takes the answer from pki.sgit.ai: the address the person was sent back to, or its `pki=` code pasted in.
    /// The issuer's public key is fetched from the register by its fingerprint and checked against it.
    func finishConnection(_ text: String, now: Date = Date()) async {
        guard busy == nil else { return }
        problem = nil
        notice = nil
        busy = "Checking the answer"
        defer { busy = nil }
        do {
            guard let data = store.get(Self.requestItem, .thisDeviceOnly), let p = try? JSONDecoder().decode(PendingRequest.self, from: data) else {
                throw PKIDelegation.Failure.notAsked
            }
            let request = PKIDelegation.Request(client: p.client, returnAddress: p.returnAddress, key: p.key, can: p.can, days: p.days, nonce: p.nonce, label: p.label)
            let key = try delegationKey()
            if case .denied(let nonce) = try PKIDelegation.answer(in: text), nonce == request.nonce {
                store.set(Self.requestItem, nil, .thisDeviceOnly)
                notice = "You said no at pki.sgit.ai. Nothing was kept."
                return
            }
            guard case .authorized(_, _, let delegation) = try PKIDelegation.answer(in: text), let issuer = delegation["iss"]?.string,
                  PKI.isFingerprint(issuer) else { throw PKIDelegation.Failure.notAnAnswer }
            let bundle = try await fetchIssuer(issuer)
            let accepted = try PKIDelegation.accept(text, asked: request, key: key, issuerBundle: bundle, today: Self.today(now))
            let saved = Connection(delegation: accepted.delegation.canonical, issuerBundle: bundle, receivedAt: now)
            store.set(Self.connectionItem, try JSONEncoder().encode(saved), .thisDeviceOnly)
            store.set(Self.requestItem, nil, .thisDeviceOnly)
            connection = saved
            notice = PKIDelegation.summary(accepted.checked)
        } catch {
            problem = "The answer was not accepted: \(error.localizedDescription)"
        }
    }

    /// The delegation the app holds, checked again today. Nil when there is none; throws when it no longer holds.
    func checkedConnection(now: Date = Date()) throws -> PKIDelegation.Checked? {
        guard let connection else { return nil }
        let d = try PKIJSON(parsing: Data(connection.delegation.utf8))
        return try PKIDelegation.check(d, issuerBundle: connection.issuerBundle, today: Self.today(now))
    }

    func forgetConnection() {
        store.set(Self.connectionItem, nil, .thisDeviceOnly)
        store.set(Self.requestItem, nil, .thisDeviceOnly)
        connection = nil
    }

    /// The issuer's public bundle, from the register's one-file summary of a record. The summary has no
    /// authority and needs none: the bundle is used only if its signing key hashes to the fingerprint asked for.
    nonisolated static func issuerFromRegister(_ fingerprint: String) async throws -> PKIBundle {
        guard PKI.isFingerprint(fingerprint),
              let url = URL(string: "https://pki.sgit.ai/id/\(fingerprint.replacingOccurrences(of: ":", with: "-")).json") else {
            throw PKIError.format("not a fingerprint")
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PKIError.format("the register has no record for \(fingerprint)") }
        return try issuerBundle(inRegisterFile: data, fingerprint: fingerprint)
    }

    nonisolated static func issuerBundle(inRegisterFile data: Data, fingerprint: String) throws -> PKIBundle {
        guard let value = try? PKIJSON(parsing: data), let inner = value["bundle"], let bundle = try? PKIBundle(json: inner) else {
            throw PKIError.format("the register's file for \(fingerprint) does not read")
        }
        guard PKI.problems(of: bundle).isEmpty, bundle.signingFingerprint == fingerprint else {
            throw PKIError.key("the register's file for \(fingerprint) carries another key")
        }
        return bundle
    }
}
