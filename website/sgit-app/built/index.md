# What is built in the sgit app

The reality file for the sgit app. **If it is not listed here as built, it does not exist.** The [design](../design/index.md) is intention; this page is fact, and it changes in the same commit as the code it describes.

Status words: [[built]] is in the repository and proven by a test that ran; [[unverified]] is written but has not been proven by a run (of CI, on a device, or against a server, as the row says); [[proposed]] does not exist.

## Built

Nothing is marked built yet: the code below has been written on the branch `work/sgit-app` and has not yet been compiled. CI is the compiler; this page changes when it has run.

| What | Where | What would prove it |
|---|---|---|
| Files over 4 MB in the vault engine [[unverified]] | `Packages/SGitVault`: `VaultStreamCipher.swift` (AES-256-GCM as a stream, so a file is sealed and opened from disk to disk), `VaultLargeTransport.swift` (sgit's upload in parts and download in ranges), `VaultLargeFiles.swift` (staging, a commit of staged files, download with every check) | `LargeFileTests` on the CI Mac; `sgit-app.yml` has sgit clone what Swift wrote and Swift read what sgit wrote. The exchange with the live server has only been run with sgit itself, not with the Swift code |
| The app [[unverified]] | `Apps/SGit/`: its own project, bundle `ai.sgit.app`, iPhone and iPad, iOS 26, SwiftUI, Apple SDK only | `sgit-app.yml`: a simulator build, a Release build, unit tests on an iPhone and an iPad simulator |
| Vaults on the device [[unverified]] | `Engine/VaultShelf.swift`, `UI/VaultsView.swift`: add by key, read key or web link, pasted or scanned as a QR code; create; keys, access token and signing key in this app's Keychain | Unit tests against a vault in a folder. Never run on a device |
| Adding photos, videos and files [[unverified]] | `Engine/Outbox.swift`, `Engine/Intake.swift`, `UI/VaultView.swift`: a selection is copied in, encrypted to disk, uploaded and committed as one signed commit; progress for each file and the whole; a failed job is kept and can be tried again or discarded; a job survives the app closing; a refused push is tried again on the new head | Unit tests: a selection read back byte for byte, a failed upload carried on by a new `Outbox`, discard, a read key refused. The pickers and the live server: never run |
| Browsing [[unverified]] | `UI/VaultView.swift`, `UI/FileView.swift`: folders, a grid or a list, thumbnails for images, an image at full size, a video player, Quick Look, Save to Photos, Share, rename, delete | The listing, rename and delete have unit tests. The screens have never been seen |
| Sharing a vault [[unverified]] | `UI/ShareVaultView.swift`: the vault key and the read key as text and QR code, with what each gives; a link for the web Vault UI | The link's form has a unit test. Whether the web Vault UI opens a vault this app wrote has not been tried |
| History [[unverified]] | `UI/HistoryView.swift`: commits, signature, the signing key's fingerprint, whether it is this device's, what changed | Unit tests for the changes and the fingerprint |

## Not built

| What | Status |
|---|---|
| TestFlight: wired in `sgit-app.yml`, switched off until there is an App Store Connect record for `ai.sgit.app` | [[proposed]]: needs the owner |
| Local-first vaults and named remotes; keys in iCloud Keychain | [[proposed]]: after issues 011 and 017 |
| A share extension; background uploads | [[proposed]] |
| A merge for colliding edits; branches | [[proposed]] |
| A read-only token that can be revoked | [[proposed]]: the format is not agreed |
| Video thumbnails; streaming a video without fetching it whole | [[proposed]] |

## Known limits

See "Limits, stated plainly" on the [design page](../design/index.md).
