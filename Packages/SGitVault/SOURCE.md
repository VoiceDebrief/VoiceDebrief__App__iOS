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
| 13 Nov 2026 | `Sources/SGitVault/VaultCreate.swift`, `Tests/SGitVaultTests/CreateTests.swift` | New: create a vault (random key, or at a given key), in the form `sgit init` writes, without a clone branch. The created vault is exported for the sgit read-back job |
| 13 Nov 2026 | `Tests/Fixtures/sgit_reads_swift.py` | Does not switch branch when the branch is `current` |
| 13 Nov 2026 | `Sources/SGitVault/VaultSync.swift`, `Tests/SGitVaultTests/SyncTests.swift` | New: `VaultSync.transfer` moves the branch `current` of a vault between two places in the server's layout (a folder on the device and a server, either way): sends only the objects the destination's head cannot reach, each checked against its id, then moves the ref with compare-and-swap. Creation and fast-forward only; when the destination is ahead or the two have diverged it reports that and writes nothing. `VaultRemoteTransport` names a transport that reads and takes batches. The pushed vault is exported for the sgit read-back job |
| 13 Nov 2026 | `Sources/SGitVault/VaultWrite.swift` | `VaultBatchOperation.batches`, `batchCount` and `batchBytes`: batches are now limited by size (3 MB before base64) as well as by count (50). `SGitVault.commit` uses it, so a large blob no longer shares a request with other objects. Behaviour is otherwise unchanged |
| 13 Nov 2026 | `Sources/SGitVault/VaultStreamCipher.swift` | New (issue 023, the sgit app session): `VaultGCMStream`, AES-256-GCM a piece at a time (AES-CTR from CommonCrypto, GHASH computed here), producing the same bytes as CryptoKit; `VaultFileCipher` seals and opens a file from disk to disk in constant memory |
| 13 Nov 2026 | `Sources/SGitVault/VaultLargeTransport.swift` | New: `VaultLargeTransport`. Over HTTP it is sgit's presigned exchange (initiate, PUT the parts, complete, cancel; read-url and byte ranges), with sgit's fallbacks for a server without it; for a folder it is a copy |
| 13 Nov 2026 | `Sources/SGitVault/VaultLargeFiles.swift` | New: `VaultBlobStager` encrypts a file to disk under its object id; `SGitVault.commit(staged:removing:…)` uploads what the server lacks, then trees, commit and the ref with compare-and-swap, with the `large` flag; `SGitVault.download` fetches a file to disk and checks id, tag, size and content hash; `VaultChange.between` |
| 13 Nov 2026 | `Sources/SGitVault/SGitVault.swift` | Added `files(in:)`: the files of any commit, so two commits can be compared. Nothing else changed |
| 13 Nov 2026 | `Tests/SGitVaultTests/LargeFileTests.swift`, `Tests/Fixtures/sgit_writes_large.py` | New: the stream cipher against CryptoKit; staged commits, resuming, a lost race; Swift reads what sgit wrote over 4 MB, and exports what it wrote for sgit to read (`.github/workflows/sgit-app.yml`) |

Nothing else differs from the source commit.
