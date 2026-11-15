import Foundation

/// `.vault-settings.json`, which the web Vault writes at the top of a vault: the vault's own name, the
/// one everybody who opens it sees. The app shows it in place of the name kept on this device.
struct VaultSettings: Decodable, Equatable {
    static let path = ".vault-settings.json"

    var vaultName: String?
    var vaultId: String?

    enum CodingKeys: String, CodingKey {
        case vaultName = "vault_name"
        case vaultId = "vault_id"
    }

    /// The name in the file, trimmed, or nil when there is none or the file cannot be read.
    static func name(in data: Data) -> String? {
        guard let settings = try? JSONDecoder().decode(VaultSettings.self, from: data),
              let name = settings.vaultName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return String(name.prefix(120))
    }
}
