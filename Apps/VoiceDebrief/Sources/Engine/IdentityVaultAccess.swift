import Foundation
import SGitVault

/// How the identity reads and writes a vault. The one file that knows the shape of `VaultBook`.
///
/// To the `work/local-vaults` session, which owns `VaultBook`: this file reaches a vault with what `VaultBook`
/// exposes today (v0.1.7: every vault is on one server, with one access token). It exists so that nothing of
/// yours had to change. When `VaultBook` gains a way to commit arbitrary files (see issue 019), the body of
/// `write` becomes one call to it and the token lookup below goes away.
@MainActor
enum IdentityVaultAccess {
    /// The bytes of a file in the vault, or nil when the vault holds no such file.
    static func read(_ path: String, in vault: SavedVault, book: VaultBook) async throws -> Data? {
        let contents = try await book.contents(of: vault)
        guard contents.files.contains(where: { $0.path == path }) else { return nil }
        return try await book.data(of: path, in: vault)
    }

    /// Writes files as one commit on the vault's `current` branch, signed by `signer`. Returns what was written.
    static func write(_ files: [String: Data], message: String, to vault: SavedVault, book: VaultBook,
                      signer: any VaultCommitSigner) async throws -> String {
        guard vault.canWrite else { throw VaultBookError.readOnly }
        guard let stored = KeychainStore().get("access-token"), let token = String(data: stored, encoding: .utf8), !token.isEmpty else {
            throw VaultBookError.noToken
        }
        let key = try await SGitVault.deriveKey(from: vault.keyText, log: book.log)
        guard let writeKey = key.writeKey else { throw VaultBookError.readOnly }
        let handle = SGitVault(key: key, server: book.server, cache: VaultBook.cacheFolder, log: book.log)
        await handle.switchBranch("current")
        _ = try await handle.pull()
        let changes: [String: Data?] = Dictionary(uniqueKeysWithValues: files.map { ($0.key, Optional($0.value)) })
        let result = try await handle.commit(changes, message: message, branch: "current", signer: signer, writeKey: writeKey,
                                             accessToken: token, writer: HTTPVaultTransport(server: book.server))
        return "Wrote \(files.count) file\(files.count == 1 ? "" : "s") in one commit signed by this device's key (\(result.objectsUploaded) objects)."
    }

    /// What a vault says about a device key: the checked statement, or nil when there is none for it.
    static func statement(forDevice fingerprint: String, in vault: SavedVault, book: VaultBook) async throws -> IdentityVouch.Checked? {
        guard let data = try await read(IdentityVouch.path(deviceFingerprint: fingerprint), in: vault, book: book) else { return nil }
        return try IdentityVouch.check(file: data)
    }
}
