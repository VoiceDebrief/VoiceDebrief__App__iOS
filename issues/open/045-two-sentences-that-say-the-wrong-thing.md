# 045: Two sentences that say the wrong thing

**Fixed: Settings says an interrupted recording is always kept and goes to the vault once transcribed; the status screen says vault keys are in iCloud Keychain by default.**

**Status:** open. From review round 3 (14 November 2026, `website/reviews/round-3/index.md`). **Owner:** the main session (`SettingsView`, `Roadmap`); the vaults session for the wording about keys.

New findings 5 and 6. Screens `settings`, `about-end`.

1. **Settings, under Library:** "A note that was interrupted is saved once it has been run again." It means
   saved to the vault. The user who once lost a recording read it as "an interrupted recording is not saved",
   against "The recording is kept" on the note itself, and said it nearly decided them against the app. Say
   what is meant: "An interrupted note's recording is kept on this device; it is written to the vault once it
   has been run again."
2. **What this build does, under vaults** (`Roadmap.swift`): "The vault's key is kept on this device only."
   Since v0.1.33 vault keys are kept in iCloud Keychain as well, unless the switch under Keys on the Vaults tab
   is off (`VaultBook.keysInICloud`, true by default), and a vault's own screen says "In iCloud Keychain, on
   your devices". The status screen must not claim what the app does not do: say where the keys are kept, or
   read it from the switch.
