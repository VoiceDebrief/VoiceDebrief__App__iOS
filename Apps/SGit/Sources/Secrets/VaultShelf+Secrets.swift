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

    /// The file that marks a vault as someone's own secrets, so that their other devices find it.
    static let homeMarker = "secrets/.my-secrets"

    func makeSecretsHome() async -> SavedVault? {
        if let known = secretsHome { return known }
        // Made on another device and carried here by iCloud Keychain.
        if let found = vaults.first(where: { contents[$0.id]?.files.contains { $0.path == Self.homeMarker } ?? false }) {
            UserDefaults.standard.set(found.id, forKey: Self.homeKey)
            return found
        }
        guard let made = await create(name: "My secrets") else { return nil }
        UserDefaults.standard.set(made.id, forKey: Self.homeKey)
        try? await put(Data("The secrets of the person who made this vault, one file each, written by the sgit app.\n".utf8),
                       at: Self.homeMarker, in: made, message: "My secrets")
        UsageLog.shared.action("secrets.home-made")
        // With an access key it goes to the server at once, so the person's other devices have it.
        if hasToken, await sendToServer(made) { return current(made) }
        return current(made)
    }

    /// The vaults that hold secrets, or could: the home first, then any vault with a `secrets/` file.
    var secretVaults: [SavedVault] {
        let home = secretsHome
        let others = vaults.filter { vault in
            vault.id != home?.id && (contents[vault.id]?.files.contains {
                SecretEntry.isSecretPath($0.path) || $0.path == Self.homeMarker
            } ?? false)
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
