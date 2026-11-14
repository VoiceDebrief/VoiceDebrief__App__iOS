# 017: Vault keys and server tokens in iCloud Keychain, on by default

**Status:** done in the code and its tests; not yet seen between two devices. Decided by the owner,
13 November 2026, and confirmed by him in the `work/local-vaults` session on 14 November. See the article
"Where each key lives".

Vault keys and remote tokens become synchronisable Keychain items, so a vault made on one device appears on
the others and survives losing a device. On by default; a switch keeps them on this device only. The
commit-signing (device) key is never synchronised.

## What was done

- `SecretStore` now names a home for every secret: `.synchronised` or `.thisDeviceOnly`. The old calls with
  no home mean this device only.
- One Keychain item per vault (`vault-<id>`), per server (`server-<id>`) and per token (`remote-token-<id>`),
  so two devices adding vaults at once do not overwrite each other. What is true of one device (whether the
  vault is on it, its heads, the last push) stays in an item of this device only.
- `SharedSecrets` keeps a copy of each on this device always, and with the switch on a synchronised copy too.
  It takes what another device made or changed, puts up what this device has never shared, and when another
  device has removed a key keeps this device's copy without putting it back.
- The switch is under Keys on the Vaults tab. Off: everything is taken onto this device, then removed from
  iCloud Keychain.
- What builds before this kept in one list is adopted, item by item, and shared.

## Only a device can show

That iCloud Keychain carries these items. Create a vault on the iPhone, wait, open the Vaults tab on the iPad
or Mac signed in to the same Apple account: the vault should be listed as on another device, or on its server
once pushed.

## Left for later

- The Vaults tab looks in iCloud Keychain when it appears, not continuously.
- Two devices that each add the same server get two entries for it.
- `IdentityKeychain` (issue 018) has its own copy of the two homes and can become a layer over `SecretStore`.
