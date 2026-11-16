import Foundation
import Observation
import SGitVault

/// The explorer layer (website/crm/explorers/): vaults whose own apps run inside the CRM, so a feature can
/// be tried, changed and used without an app build, and a switch per feature saying whether it runs
/// natively or in a vault app. Keys are in the Keychain; only names, ids and switches are in settings.
struct VaultApp: Codable, Identifiable, Hashable, Sendable {
    var id: String          // the vault id
    var name: String
    var addedAt: Date
    var canWrite: Bool
}

@MainActor
@Observable
final class VaultApps {
    enum Problem: LocalizedError, Equatable {
        case notAKey, alreadyThere

        var errorDescription: String? {
            switch self {
            case .notAKey: return "That is not a vault key or a read key."
            case .alreadyThere: return "That vault is already in the list."
            }
        }
    }

    private let store: any SecretStore
    private let defaults: UserDefaults
    private(set) var apps: [VaultApp] = []
    /// Which vault app runs each section that is switched away from its native screen, by section.
    private(set) var switches: [String: String] = [:]

    static let listKey = "crm.vault-apps"
    static let switchesKey = "crm.feature-switches"
    static func secretName(_ id: String) -> String { "vault-app-key-\(id)" }

    init(store: any SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.listKey), let list = try? JSONDecoder().decode([VaultApp].self, from: data) { apps = list }
        switches = (defaults.dictionary(forKey: Self.switchesKey) as? [String: String]) ?? [:]
        switches = switches.filter { pair in apps.contains { $0.id == pair.value } }
    }

    /// Adds a vault by its key (a vault key or a read key, typed, pasted or scanned).
    @discardableResult
    func add(keyText raw: String, name: String) async throws -> VaultApp {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VaultKey.classify(text) != nil else { throw Problem.notAKey }
        let key = try await Task.detached(priority: .userInitiated) { try VaultKey.parse(text) }.value
        guard !apps.contains(where: { $0.id == key.vaultId }) else { throw Problem.alreadyThere }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let app = VaultApp(id: key.vaultId, name: trimmed.isEmpty ? "Vault \(key.vaultId)" : trimmed, addedAt: Date(), canWrite: key.canWrite)
        store.set(Self.secretName(app.id), Data(text.utf8))
        apps.append(app)
        persist()
        return app
    }

    func keyText(for app: VaultApp) -> String? {
        store.get(Self.secretName(app.id)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The key to share as a QR code: the read key unless the full key is asked for and held.
    func shareText(for app: VaultApp, full: Bool) async -> String? {
        guard let text = keyText(for: app) else { return nil }
        if full { return text }
        return try? await Task.detached(priority: .userInitiated) { try VaultKey.parse(text).exportReadKey() }.value
    }

    func remove(_ app: VaultApp) {
        store.set(Self.secretName(app.id), nil)
        apps.removeAll { $0.id == app.id }
        switches = switches.filter { $0.value != app.id }
        persist()
    }

    /// Runs `section` in `app`, or natively when `app` is nil.
    func set(_ section: CRMSection, to app: VaultApp?) {
        switches[section.rawValue] = app?.id
        persist()
    }

    func app(for section: CRMSection) -> VaultApp? {
        guard let id = switches[section.rawValue] else { return nil }
        return apps.first { $0.id == id }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(apps), forKey: Self.listKey)
        defaults.set(switches, forKey: Self.switchesKey)
    }
}
