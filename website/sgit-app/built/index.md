# What is built in the sgit app

The reality file for the sgit app. **If it is not listed here as built, it does not exist.** The [design](../design/index.md) is intention; this page is fact, and it changes in the same commit as the code it describes.

Status words: [[built]] is in the repository and proven by a test that ran; [[unverified]] is written but has not been proven by a run (of CI, on a device, or against a server, as the row says); [[proposed]] does not exist.

## Built

Proven by `sgit-app.yml` run 2 (13 November 2026, commit `c171e00`), green in all three jobs. Nothing here has run on a device or spoken to a server from the app: where that matters the row says so.

| What | Where | How it is tested |
|---|---|---|
| Files over 4 MB in the vault engine [[built]] | `Packages/SGitVault`: `VaultStreamCipher.swift` (AES-256-GCM as a stream, so a file is sealed and opened from disk to disk), `VaultLargeTransport.swift` (sgit's upload in parts and download in ranges), `VaultLargeFiles.swift` (staging, a commit of staged files, download with every check) | `LargeFileTests` on the CI Mac: the stream cipher byte for byte against CryptoKit; tampered files refused; a failed upload carried on; a lost race. `sgit-app.yml`: sgit clones a vault Swift wrote with files of 5 and 9 MB and verifies its signatures, and Swift reads a vault sgit wrote. All of that is against a folder. The exchange with the live server (signed URLs) is written and [[unverified]]: it has been run with sgit itself, not with the Swift code |
| The app builds and its tests pass [[built]] | `Apps/SGit/`: its own project, bundle `ai.sgit.vaults.app`, iPhone and iPad, iOS 26, SwiftUI, Apple SDK only | `sgit-app.yml`: a simulator build, a Release build for a device, unit tests on an iPhone and an iPad simulator |
| Adding files, underneath the screens [[built]] | `Engine/Outbox.swift`, `Engine/VaultShelf.swift`: a selection is copied in, encrypted to disk, uploaded and committed as one signed commit; a failed job is kept and is finished by a new `Outbox` after a restart; discard; a read key is refused; rename and delete as commits; what a commit changed; the signer's fingerprint | Unit tests on the simulators, against a real vault held in a folder: a 5 MB file read back byte for byte through the cache |
| Vaults on the device [[unverified]] | `UI/VaultsView.swift`: add by key, read key or web link, pasted or scanned as a QR code; create; keys, access token and signing key in this app's Keychain | Compiles. The Keychain, the camera and the live server: never run |
| Adding photos, videos and files, the screens [[unverified]] | `Engine/Intake.swift`, `UI/VaultView.swift`: the Photos picker and the Files picker, progress for each file and the whole, Try again and Discard | Compiles. The pickers have never been used |
| Browsing [[unverified]] | `UI/VaultView.swift`, `UI/FileView.swift`: folders, a grid or a list, thumbnails for images, an image at full size, a video player, Quick Look, Save to Photos, Share, rename, delete | The listing has unit tests. The screens have never been seen |
| Sharing a vault [[unverified]] | `UI/ShareVaultView.swift`: the vault key and the read key as text and QR code, with what each gives; a link for the web Vault UI | The link's form has a unit test. Whether the web Vault UI opens a vault this app wrote has not been tried |
| History [[unverified]] | `UI/HistoryView.swift`: commits, signature, the signing key's fingerprint, whether it is this device's, what changed | What it shows has unit tests; the screen has never been seen |

## Not built

| What | Status |
|---|---|
| TestFlight: wired in `sgit-app.yml`; the owner has made the App Store Connect record and set the switch. No build has been uploaded yet | [[unverified]] |
| Local-first vaults and named remotes; keys in iCloud Keychain | [[proposed]]: after issues 011 and 017 |
| A share extension; background uploads | [[proposed]] |
| A merge for colliding edits; branches | [[proposed]] |
| A read-only token that can be revoked | [[proposed]]: the format is not agreed |
| Video thumbnails; streaming a video without fetching it whole | [[proposed]] |

## Known limits

See "Limits, stated plainly" on the [design page](../design/index.md).
