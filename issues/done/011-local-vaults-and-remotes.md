# 011: Vaults are local first; a server is a remote

**Status:** done in the code and its tests; not yet run on a device. See the article "The vault is a version-controlled store".

The Vaults tab asked for an access token before creating a vault. Creating a vault needs no server.

## What was done

- A vault is created, committed to, read and browsed in a folder on the device (`Application Support/vaults/`),
  through the engine's `FolderVaultTransport`. No token, no network.
- Servers are named remotes: a name, an address and an access token in the Keychain. A vault has none or one.
- Push and pull are explicit (`VaultSync.transfer` in the engine): only what the other side lacks is sent, the
  ref moves last with compare-and-swap, and only forward. When both sides have changed it says a merge is
  needed and writes nothing.
- Each vault says where it is: on this device only, not yet pushed, pushed (when), ahead of the server, or
  push failed with the reason.
- Vaults from v0.1.5 to v0.1.9 stay attached to `dev.send.sgraph.ai` and work as before; "Keep a copy on this
  device" brings one down.
- `ios-vault.yml` has `sgit` clone a vault that was created in one folder and pushed to another.

## Left for later

- A merge when both sides have changed (issue 006).
- Branches other than `current`; several servers for one vault; pushing automatically after a save.
- The first push of a vault from the app to the live server, and the first pull: only a device can show these.
