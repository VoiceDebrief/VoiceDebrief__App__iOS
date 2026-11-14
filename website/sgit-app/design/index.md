# The sgit app: design for milestone one

sgit as a native app for iPhone, iPad and Mac: vaults, files and commits, with the same encrypted format as the `sgit` command and the web Vault UI. This page is intention. [What is built](../built/index.md) says how much of it exists. It lives in this repository for now, beside VoiceDebrief for iOS, and shares its vault engine; it will move to a repository of its own.

## Why it starts here

The owner's words, 13 November 2026: the team needs to share photos, videos and large files, and "at the moment there isn't an easy way to do it". So the first milestone is narrow: a person picks photos, videos or any files on a phone, they go into a vault, and a teammate can open them. Managing vaults and commits grows from there towards what the web Vault UI does.

## The jobs, in order

1. **Put files in a vault without losing them.** A selection is copied into the app before anything else happens. From then on a failed upload, a closed app or a lost connection can be taken up again.
2. **Find and open what is in a vault.** Folders, thumbnails, a full-size view, a video player.
3. **Give the vault to somebody**, knowing what that gives them.
4. **See what happened.** Every commit, which key signed it, what it changed.

## What was read first

| Source | What it settled |
|---|---|
| `sgit-ai` 0.27.0 (the Python package) | The format and the protocol. A blob over 4 MB encrypted is uploaded in parts of 10 MB to URLs the server signs, flagged `large` in its tree entry, and read back from a signed URL in ranges of 8 MB |
| The web Vault UI: its JavaScript as served at vault.sgraph.ai, read by this session; its source (the Send repository at commit `da293d4`, 18 October 2026), read by the parent session | The features and the words. It encrypts each file whole and sends it in a batch, and refuses a write over 3 MB from a vault app; its own source says a large upload through signed URLs "is not yet supported". It does read large files through a signed URL. Its library can move a branch with compare-and-swap (`pushIfMatch`), but its screens use the unconditional `push`, which the source notes can drop somebody else's commits |
| The server's published API description | Reading needs no access token, including the signed URL for a large object. Writing needs the access token and the vault's write key |
| The live server, with `sgit` itself | The exchange for a large object works on `dev.send.sgraph.ai` as the package describes it (a throwaway vault, destroyed afterwards) |

The two source repositories could not be attached to this session. What is said about the web Vault UI's source is the parent session's reading of it, passed on; the rest is from published code.

## Decisions

| | Decision |
|---|---|
| One selection, one commit | Everything picked together becomes one signed commit on the branch `current`, with the message the web Vault UI writes: `Add IMG_0001.HEIC`, or `Add 3 files: a, b, c` |
| Staging | A picked file is copied into the app, then encrypted to disk under its object id, then uploaded, then named in the commit. Each step is recorded, so a retry sends only what the server lacks |
| A refused push | If somebody else committed first the server refuses the move (compare-and-swap). Adding files needs no merge: the same staged files are committed again on the new head, automatically |
| Large files | Encrypted and decrypted from disk to disk, a megabyte at a time. Uploaded in parts, three at a time; downloaded in ranges, three at a time. See "Limits" |
| Where a file goes | Into the folder that is open, under its own name. A name already taken gets a number |
| Reading | A file is fetched and decrypted when it is opened. The decrypted copy is in the app's cache folder only, which the system may empty, and which Settings can empty |
| Where a vault lives | A vault you create is made and kept on this device: no account, no token, no network, and it takes files at once. It goes to a server when you choose to share it, which is the first time an access token is asked for, with the reason. From then on the server is where it lives and this device reads and writes it there, as it does a vault added by its key. One server (`dev.send.sgraph.ai`) for now |
| Keys | Vault keys, the access token and the device's commit-signing key are in this app's Keychain, on this device only. This app does not share a Keychain with VoiceDebrief |
| Honesty | No screen says a file is in the vault before the commit that names it has been pushed and read back |

## The words

The owner's and sgit's: **vault**, **vault key** (reads and writes), **read key** (reads only), **access token** (the web UI calls it an access key), **commit**, **history**, **branch**. The app says **Add** for putting files in, **Refresh** for fetching the latest, and **Send to the server** for the one push a vault made on the device needs.

## The screens

**Vaults.** The vaults this device knows. Add one by pasting its key or scanning a QR code; create one. Each row says whether the key can write.

**A vault.** The folder that is open: folders first, then files, as a grid of thumbnails or a list. Add (from Photos, from Files), New folder by naming one when adding, Refresh, Share, History. Uploads in progress sit at the top with a bar for each file and one for the whole selection, and a failed one says why and offers Try again and Discard.

**A file.** An image at full size with zoom; a video in the system player; anything else in Quick Look. Save to Photos and Share. Delete and rename are a commit each.

**Share.** The vault key as text and as a QR code, under a plain statement: whoever holds it can read everything, add, change and delete, and it cannot be taken back. Below it the read key, for somebody who should only look. See "Giving somebody the vault".

**History.** The commits, newest first: the message, the time, the short id, the fingerprint of the key that signed it and whether the signature verified, and whether that key is this device's. A commit opens to the files it added, changed and removed.

**Settings.** The server and the access token; this device's signing key (its fingerprint); the cache and a button to empty it; every step the vault engine has taken; the version.

## Giving somebody the vault

What exists today, and what each gives:

| Mechanism | Where it exists | What the other person gets |
|---|---|---|
| The vault key, `passphrase:vault id` | sgit, the web UI, this app | Everything, for ever: read, write, delete. It cannot be revoked; the only remedy is a new vault |
| The same key as a link, `vault.sgraph.ai/#key` | The web UI | The same, opened in a browser with nothing to install |
| A read key, `sgit_private_read_…` | sgit and this app's engine. The web UI shows it but cannot yet open with it | Read only, live, for ever. Cannot be revoked |
| A read-only token, `ro-word-word-1234` | The web UI's token manager, marked there as a test harness | Read only, live, with an expiry and a way to revoke it. The token unlocks a small encrypted record on the server that holds the read key |
| `sgit publish` | sgit | A static, read-only copy for a website |

There is no snapshot share: nothing gives "these files as they are now and nothing later".

**Proposal.** Milestone one ships the first three, because they need nothing new on any side: the key as text and QR, the web link, and the read key. For a team sharing photos that is enough, and the warning is on the screen. The right next step is the read-only token, because it is the only one that can be taken back, but it should be built once: the web UI's version is a test harness, and the app, sgit and the web UI should agree on one format first. That is a question for the owner, and is issue 104.

## Limits, stated plainly

- **The format encrypts a file as one AES-GCM message.** sgit and the web UI therefore hold a whole file, and its whole ciphertext, in memory. The app does not: it computes the same bytes as a stream. Its limit is free space on the device (the staged copy and the ciphertext exist together until the upload ends, so about twice the file), and AES-GCM's own limit of about 64 GB a message.
- **What could not be avoided.** Each upload part is held in memory while it is sent: three parts of 10 MB. A blob that sgit deflated and that is over 4 MB is inflated in memory, up to 64 MB. A server without signed URLs (a self-hosted one) takes a large object in one request, which the app allows up to 64 MB. Thumbnails are made from the full image, so a folder of photographs is fetched whole the first time it is shown.
- **The other end.** A teammate opening a large video in the web UI needs it to fit in the browser's memory; `sgit clone` on a computer needs it to fit in memory once.
- **A vault on this device only is on this device only.** Until it is sent to a server there is one copy. Forgetting it deletes it, and the app says so before it does.
- **An upload stops when the app is suspended.** It is taken up again when the app returns: parts already sent in an unfinished object are sent again, finished objects are not. Background uploads are after milestone one.
- **A vault with packs** (objects stored as zips) is refused, as it is by the engine today.

## Milestone one

1. Add a vault by key or QR code; create one.
2. Add photos, videos and files; progress for each and overall; retry and discard; nothing picked is lost.
3. Files over 4 MB, written and read, checked against sgit in both directions by CI.
4. Browse: folders, thumbnails, full size, video, Quick Look, Save to Photos, Share.
5. Share the vault: key, QR code, web link, read key, with the warning.
6. History: commits, signer, what changed.

## After it, in this order

1. A vault that stays on the device after it is shared, with push and pull and a choice of servers, as VoiceDebrief has since issue 011. That needs two things first: a merge for when two people add at once (today the app commits straight to the server, where a refused push is simply tried again), and a way to keep a vault's trees on the device without fetching every video in it. Then keys in iCloud Keychain (017).
2. A share extension: "send to vault" from Photos and Files.
3. Background uploads.
4. A file-level merge for edits and deletions that collide (adding already needs none).
5. Branches: list, switch, create.
6. A read-only token that can be revoked, once its format is agreed.
