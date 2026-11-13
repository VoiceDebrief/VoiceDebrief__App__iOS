# 028: The device key signs every commit, and the vault says whose device it is

**Status:** open. For the `work/local-vaults` session, which owns `VaultBook` and `VaultsView`. From the
`work/identity` session (issue 018), which was asked not to edit those files.

Issue 018 built the device key (`Engine/IdentityDeviceKey.swift`): a P-256 key in the Secure Enclave where there
is one, otherwise in the Keychain for this device only, wiped on the first use after a reinstall. It is a
`VaultCommitSigner`. Today `VaultBook.commitSigner()` still makes its own software key (`commit-signer` in the
Keychain) and signs every debrief with that. So a vault holds commits by two keys from one device, and only the
identity's own commit is signed by the key the vouching statement names.

## What to change, in `VaultBook`

1. `commitSigner()` returns `any VaultCommitSigner` and hands out the device key:

   ```swift
   func commitSigner() throws -> any VaultCommitSigner {
       try IdentityBook.shared.deviceSigner()
   }
   ```

   Tests that need a signer without a Keychain can keep `SoftwareCommitSigner`, or make a device key over
   memory: `IdentityDeviceKey.current(store: IdentityMemoryKeyStore(), defaults: …, useSecureEnclave: false)`.
   The `commit-signer` Keychain item can then be deleted on first run. Commits it signed stay checkable: its
   public half is in each vault under `bare/keys/`.

2. A way to commit arbitrary files, which `save(run:audioURL:to:)` can then be written on top of:

   ```swift
   func write(_ files: [String: Data], message: String, to vault: SavedVault) async throws -> String
   ```

   `Engine/IdentityVaultAccess.swift` is the one file in the identity that knows the shape of `VaultBook`. It
   writes the vouching statement with what `VaultBook` exposes today, without its bookkeeping. Replace the body
   of `IdentityVaultAccess.write` with a call to the method above and delete the rest of it.

## What to change, in `VaultsView`

In a vault's detail, one row says what the vault holds about this device:

```swift
IdentityVouchRow(vault: vault, vaults: book)
```

It reads `identity/devices/<device fingerprint>.json`, checks it, and shows "This device is vouched for by
<fingerprint>", with a button to write the statement when there is none. The same row is on the Identity screen.

For each commit in the history, the two-step check is `IdentityVouch.covers(checked, commitKeyPEM:)`: the
statement names the key that signed. The commit's key is at `bare/keys/<key id>`.

## Done when

A debrief saved from the app is signed by the device key, the vault's detail says who vouches for that key, and
`sgit` still clones and verifies the vault.
