# Where this package came from

`SGitVault` was copied from `PrompTugal/PrompTugal__App__iOS`, path `Packages/SGitVault`, at commit
`bf76d2937d0dbf467ce5c4b1a61c7f83dd752f84` (release v0.4.103), on 13 November 2026.

It is a copy, not a dependency, so the two can drift. Until it is extracted into a repository both apps
depend on, keep this file exact: a fix made here should be offered there, and a fix made there should be
brought here by diff against the commit above.

## Changes made in this repository

| Date | File | Change |
|---|---|---|
| 13 Nov 2026 | `Sources/SGitVault/VaultDoor.swift` | Added `door(fromSecret:site:counter:)`, `prfSalt(site:)` and `pkiSite`, so a door can be derived for a site other than the one compiled in. The existing `door(fromSecret:counter:)` and `prfSalt` are unchanged in behaviour and now call the new function |
| 13 Nov 2026 | `Tests/SGitVaultTests/SiteDoorTests.swift` | New: the vector published at `newsroom.sgit.ai/passkey/vectors.json`, and that the default site is unchanged |

Nothing else differs from the source commit.
