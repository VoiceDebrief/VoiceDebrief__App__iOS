# 017: Vault keys and server tokens in iCloud Keychain, on by default

**Status:** open. Decided by the owner, 13 November 2026. Owner of the code: the `work/local-vaults` session.
See the article "Where each key lives".

Vault keys and remote tokens become synchronisable Keychain items, so a vault made on one device appears on
the others and survives losing a device. On by default; a switch keeps them on this device only. The
commit-signing (device) key is never synchronised.
