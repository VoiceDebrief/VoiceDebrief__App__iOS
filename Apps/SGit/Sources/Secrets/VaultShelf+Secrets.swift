import Foundation
import SGitVault

/// Reading and writing secrets: each is one file, read into memory and never into the file cache.
extension VaultShelf {
    static let homeKey = "secrets.home"

    /// The vault where new secrets go unless another is chosen: "My secrets", made on this device on first use.
    var secretsHome: SavedVault? {
        guard let id = UserDefaults.standard.string(forKey: Self.homeKey) else { return nil }
        return vaults.first { $0.id == id }
    }

    func makeSecretsHome() async -> SavedVault? {
        if let known = secretsHome { return known }
        guard let made = await create(name: "My secrets") else { return nil }
        UserDefaults.standard.set(made.id, forKey: Self.homeKey)
        UsageLog.shared.action("secrets.home-made")
        return made
    }

    /// The vaults that hold secrets, or could: the home first, then any vault with a `secrets/` file.
    var secretVaults: [SavedVault] {
        let home = secretsHome
        let others = vaults.filter { vault in
            vault.id != home?.id && (contents[vault.id]?.files.contains { SecretEntry.isSecretPath($0.path) } ?? false)
        }
        return (home.map { [$0] } ?? []) + others
    }

    /// Every secret in one vault, decrypted in memory. A file that is not a secret is left out.
    func secrets(in vault: SavedVault) async throws -> [SecretEntry] {
        let listing = try await load(vault)
        let handle = try await open(vault)
        var out: [SecretEntry] = []
        for file in listing.files where SecretEntry.isSecretPath(file.path) {
            if let entry = try? SecretEntry.decode(try await handle.read(file.path)) { out.append(entry) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Writes one secret as one signed commit: added, or changed in place.
    func save(_ entry: SecretEntry, in vault: SavedVault, isNew: Bool) async throws {
        var entry = entry
        entry.updatedAt = Date()
        entry.changedBy = deviceKeyId
        entry.fields = entry.filled
        let message = VaultNaming.fit((isNew ? "Add secret " : "Change secret ") + entry.name)
        try await put(try entry.encoded(), at: entry.path, in: vault, message: message)
        UsageLog.shared.action(isNew ? "secret.add" : "secret.change")
    }

    func delete(_ entry: SecretEntry, in vault: SavedVault) async throws {
        guard let file = contents[vault.id]?.files.first(where: { $0.path == entry.path }) else { return }
        try await delete(file, in: vault)
        UsageLog.shared.action("secret.delete")
    }
}
