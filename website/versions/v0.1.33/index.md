# What changed in v0.1.33

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

Vault keys and server tokens in iCloud Keychain, on by default (issue 017, the owner's decision). Each vault's key, each server and each token is now a Keychain item of its own, kept on this device and, unless a new switch under Keys on the Vaults tab is turned off, in iCloud Keychain too, so that a vault made on one device can appear on the owner's others and survive losing a device. A vault whose key has arrived says where the vault itself is: on its server, or still only on another device. Turning the switch off moves everything back to this device only. The key that signs a device's commits is never synchronised. In test: the logic is unit-tested with an in-memory Keychain; that Apple carries the items between two real devices has not been seen.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
