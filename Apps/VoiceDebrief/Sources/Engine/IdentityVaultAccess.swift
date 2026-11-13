import Foundation
import SGitVault

/// How the identity reads and writes a vault. The one file that knows the shape of `VaultBook`.
///
/// To the session that owns `VaultBook`: this file reaches a vault with what `VaultBook` exposes, so that
/// nothing of yours had to change. It writes only to a vault kept on this device, straight into its folder,
/// as `save(run:audioURL:to:)` does, but it cannot reach your bookkeeping: after a write here `localHead` is
/// stale, so the status line does not say "ahead" until the next push or save (the push itself reads the
/// folder and sends the commit). When `VaultBook` gains a way to commit arbitrary files (issue 025), the body
/// of `write` becomes one call to it.
@MainActor
enum IdentityVaultAccess {
    /// The bytes of a file in the vault, or nil when the vault holds no such file.
    static func read(_ path: String, in vault: SavedVault, book: VaultBook) async throws -> Data? {
        let contents = try await book.contents(of: vault)
        guard contents.files.contains(where: { $0.path == path }) else { return nil }
        return try await book.data(of: path, in: vault)
    }

    /// Writes files as one commit on the `current` branch of a vault kept on this device, signed by `signer`.
    /// No network and no token: pushing to the vault's server is a separate step, on the Vaults tab.
    static func write(_ files: [String: Data], message: String, to vault: SavedVault, book: VaultBook,
                      signer: any VaultCommitSigner) async throws -> String {
        let now = book.current(vault)
        guard now.canWrite else { throw VaultBookError.readOnly }
        guard now.onDevice else { throw VaultBookError.notOnDevice }
        let key = try await SGitVault.deriveKey(from: now.keyText, log: book.log)
        guard let writeKey = key.writeKey else { throw VaultBookError.readOnly }
        let local = FolderVaultTransport(root: book.localRoot, perVaultSubfolder: "")
        let handle = SGitVault(address: VaultAddress(vaultId: key.vaultId, server: VaultAddress.defaultServer), readKey: key.readKey,
                               cache: book.cacheRoot, log: book.log, transport: local)
        await handle.switchBranch("current")
        _ = try await handle.pull()
        let changes: [String: Data?] = Dictionary(uniqueKeysWithValues: files.map { ($0.key, Optional($0.value)) })
        let result = try await handle.commit(changes, message: message, branch: "current", signer: signer, writeKey: writeKey,
                                             accessToken: nil, writer: local)
        let pushed = book.remote(now.remoteId).map { " Not yet on \($0.name): push it from the Vaults tab." } ?? ""
        return "Wrote \(files.count) file\(files.count == 1 ? "" : "s") in one commit signed by this device's key (\(result.objectsUploaded) objects), on this device.\(pushed)"
    }

    /// What a vault says about a device key: the checked statement, or nil when there is none for it.
    static func statement(forDevice fingerprint: String, in vault: SavedVault, book: VaultBook) async throws -> IdentityVouch.Checked? {
        guard let data = try await read(IdentityVouch.path(deviceFingerprint: fingerprint), in: vault, book: book) else { return nil }
        return try IdentityVouch.check(file: data)
    }
}
