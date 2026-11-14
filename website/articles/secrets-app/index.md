# A secrets app that keeps one file where you already keep things

**Kind:** research, a storage design and a build plan. **From:** the owner's voice note of 14 November 2026, after trying the Secrets part of SGit Vaults: "even just that is a crazy feature; we should just ship it". Written up by the secrets-app research session the same day. **Nothing on this page is built unless it says so.** The only record of what exists is [what is built](../../built/index.md) (and, for SGit Vaults, [its own reality file](../../sgit-app/built/index.md)).

The idea in one line: **a cheap password and secrets manager that just works, where the vault is one small encrypted file in your own iCloud Drive, rewritten on every change, opened by a key that never reaches us, with our server only ever an extra copy.**

[![Three locks open the vault key: iCloud Keychain, a passkey, a printed recovery code. The vault lives on the device. After every change it is written to four stores: one file in iCloud Drive, this device, a copy you keep, and optionally the SG/Send server. Two devices that edited offline join by union of objects, then merge.](../../assets/diagrams/secrets-app-storage.svg)](../../assets/diagrams/secrets-app-storage.svg)

## 1. What the owner asked for

His words where they matter:

- **Ship the Secrets screens as their own product**: "an easy, cheap password and secrets manager" that "just works", on what exists: an encrypted, version-controlled vault, all cryptography on the device, a server that sees only ciphertext.
- **Do not depend on our server by default.** "Our services are not ready to provide that level of resilience; this becomes mission critical", and a server connection "breaks the whole model". Keep the vault as **one small encrypted file** (a zip of the vault) in storage the person already has, above all iCloud Drive, rewritten on every change, with a few past versions kept, and refreshed when the app opens.
- **Several stores at once**: iCloud Drive, a local file, a downloaded copy that the `sgit` command can open, and optionally SG/Send for online access. Never the server as the default.
- **Options for the key**: today it is in iCloud Keychain; also a passkey wrapping the file, or something else.
- **Sharing later**: swap public keys by QR code or copy and paste, seal a vault key to the other person, share with a browser session.
- **Pricing per use**, like VoiceDebrief's credit, in 1p steps.

## 2. What exists in this repository today

Read on 14 November 2026. Labels as in the reality files: *built* is tested in CI, *unverified* is written and compiled but not yet proven on a device, *proposed* does not exist.

| Part | Where | Status |
|---|---|---|
| Secrets screens: kinds login, device passcode, Wi-Fi, card, note, token, vault key, read key, access key, recovery codes; each secret one encrypted JSON file (`sgit.ai/secret/v1`) in a vault's `secrets/` folder, each change one signed commit; values behind Face ID, copied for two minutes; a strong-password maker; "My secrets" made on first use | `Apps/SGit/Sources/Secrets/` (`SecretEntry.swift`, `SecretsView.swift`, `VaultShelf+Secrets.swift`) | Unverified |
| Vaults on the device with no server: the server's own layout (`bare/data`, `refs`, `indexes`, `keys`) in a folder under Application Support | `VaultBook`, `VaultShelf`, `Packages/SGitVault` | Unverified (CI tests with folders) |
| Vault keys and access keys in iCloud Keychain, one synchronisable item each, a switch to keep them on one device | `Engine/SecretStore.swift` in both apps | Unverified; iCloud Keychain itself cannot be tested in CI |
| Push and pull to a server: creation and fast-forward only. **When both sides have changed it says so and writes nothing: merge is not built in Swift** | `Packages/SGitVault/Sources/SGitVault/VaultSync.swift` | Unverified against the live server |
| The passkey door: a vault key derived from a passkey's PRF output, or from a 26-character recovery code in its place | `VaultDoor.swift` | The derivation is built and matches the website's vectors; **the passkey ceremony in a native app is not built** (issue 003) |
| Cards, sealed messages, first contact (an access key sealed to a newcomer's card), a secrets store that remembers who gave what | `Packages/SGitPeople` | Unverified, on no screen |
| Paying for anything | `Model/Prices.swift`, the credit ledger in VoiceDebrief | Ledger and price list built; the App Store purchase is written and switched off, so no money moves |
| A vault as one file in iCloud Drive, several stores, a merge after offline edits, a third app | | **Proposed: this page** |

Two things were checked for this article with the real `sgit` command (sgit-ai 0.27.0, from PyPI, in this session):

1. **A vault zipped as one file opens with the command line.** A vault was made in sgit's in-memory server, its store written out as a folder (`bare/data`, `bare/refs`, `bare/indexes`, `bare/keys`) and zipped: 31 objects after five commits, **17,125 bytes**. Unzipped elsewhere, `sgit clone --transport local --base-url <folder> <vault key> out` cloned it, the files were there and `sgit history log` showed every commit, including the merge.
2. **sgit merges two copies that changed apart.** Two clones of one vault each committed while "offline" (different secrets). The second push pulled, merged into a merge commit, and pushed: all three secrets present. When both changed **the same** secret, `pull` reported `conflicts: ['secrets/wifi.json']` and asked for a resolution.

So the format and the merge exist in sgit's Python. What does not exist is the same merge in Swift, and the file store.

## 3. The field: how other managers store, sync, recover and share

Prices move often and many come from aggregators; treat them as approximate. The fuller field study, with sharing and team features, is the [opportunity brief](../../sgit-app/secrets/opportunity/index.md) written for SGit Vaults.

| Product | Where the vault lives | Sync | If every device is lost | Sharing | Price (approx.) |
|---|---|---|---|---|---|
| Apple Passwords | iCloud Keychain, end-to-end encrypted | Apple, invisible | Apple Account recovery: trusted number plus a recovery contact or recovery key; without them the data can be gone | Shared groups; owner and members, no roles | **Free, built in** |
| 1Password | Vendor cloud | Vendor | Secret Key plus account password (an Emergency Kit to print) | Shared vaults | About $48 a year individual, $72 family, from March 2026; no free plan |
| Bitwarden | Vendor cloud, or self-hosted | Vendor or your server | Master password; emergency access on paid plans | Organisations; a free one holds two people | Free; Premium $19.80 a year, Families $47.88 (raised in 2026) |
| Proton Pass | Vendor cloud | Vendor | Proton account recovery | Shared vaults on paid plans | Free; Plus about $2 to $3 a month |
| Dashlane | Vendor cloud | Vendor | Account recovery options | Sharing, groups | Free plan reported withdrawn in 2025; paid plans only |
| Keeper | Vendor cloud | Vendor | Account recovery | Shared folders with permissions | Limited free; Family about $46 a year |
| Enpass | **A file in your own cloud** (iCloud, Dropbox, Google Drive, OneDrive, WebDAV) or Wi-Fi sync; no Enpass servers | The cloud you chose | Master password; nothing at Enpass to recover | Share an item; a shared vault through a shared cloud folder | Subscription or a one-off licence; figures vary widely |
| KeePass, KeePassXC | **One `.kdbx` file** wherever you put it | Whatever syncs the file | Master password and optional key file; nothing to recover | Share the file and its password | Free, open source |
| Strongbox (KeePass on Apple) | A `.kdbx` file, by default in **its own iCloud Drive folder**; or Strongbox Sync on CloudKit | iCloud Drive or CloudKit | As KeePass | As KeePass | Free with a Pro tier or lifetime |

What the file-based ones teach, because they are closest to the owner's idea:

- **A file in iCloud Drive works, and it has a known failure.** Strongbox recommends keeping the database in its own iCloud folder, which the app watches; it blames numbered duplicate copies on slow iCloud sync; and it now recommends its own CloudKit sync instead. Guides on KeePass sync warn that iCloud and Google Drive behave as last-writer-wins: the losing device's change leaves the active file unless the app merges.
- **KeePass merges at the entry level.** KeePassXC and Strongbox can merge two databases using each entry's modification time and its own history. That is good, but it is a merge by timestamp of a whole entry; there is no common ancestor, so an entry changed on both sides keeps the later one and puts the other in its history.
- **Enpass proves people will choose their own cloud** to avoid trusting a vendor's servers.

## 4. Where an sgit vault is genuinely different, and where it is not

**Not different, and we should say so:**

- **Apple Passwords is free, built in, fills passwords and passkeys everywhere, and syncs with no thought.** For one person who lives on Apple devices and never needs a file, a history or a non-Apple share, it is enough. We do not beat it on convenience; AutoFill alone is a capability we have not switched on.
- **Strongbox already keeps an encrypted file in iCloud Drive**, with Face ID, AutoFill, history per entry and a merge. KeePass history exists too.
- **Enpass already lets you choose your own cloud.**
- **Encryption on the device and a server that sees only ciphertext** is what every serious manager claims.

**Genuinely different:**

1. **A merge with a common ancestor, not a timestamp.** Each copy of the vault is a commit graph. Two devices that changed different secrets merge with no question; one secret changed on both is shown side by side, with the version both started from. KeePass guesses by time; iCloud alone drops one side.
2. **The file cannot be half-merged into nonsense.** Objects are named by the hash of their ciphertext, so two copies of the file join by plain union: the same name is always the same bytes. Only the two heads need merging.
3. **Signed history of every change**: which device changed the Wi-Fi password and when, with the earlier value one step back, kept in the format itself rather than per entry.
4. **Secrets and files together.** A secret is a file in a vault; the same vault can hold the scan of a passport, a recovery sheet, an SSH key file, a 300 MB backup.
5. **One format, several stores, no lock-in.** The same vault can be a file in iCloud Drive, a folder on a Mac, a copy on a USB stick and a remote on SG/Send, all at once, and the open `sgit` command reads any of them.
6. **Sharing by key exchange that no server takes part in.** The key you seal to comes from a card you scanned in person, not from a vendor's directory: the weakness behind the 2026 ETH Zurich attacks on Bitwarden, LastPass and Dashlane (see the brief).
7. **Agents.** An AI session has a card and an inbox in this design; it can be given one secret, sealed to it, with a record.

The honest summary: the first product competes with Strongbox and Enpass on "your file, your cloud", and adds a real merge, history and a path to sharing. It does not compete with Apple Passwords on convenience until AutoFill is in.

## 5. The storage design

### 5.1 The vault on the device is the truth

Every device keeps the whole vault in the layout the SGit app already uses (`Application Support/vaults/<vault id>/bare/…`). Reading, adding and changing need no network and no store. Each store is a copy that is **written after every change** and **read and merged when the app opens or comes to the front**. This is the "a vault is local first and a server is a remote" position, with iCloud Drive as the first remote.

A consequence that matters for "mission critical": **a write that iCloud loses is not a lost secret.** The device still holds its commits, and its next write carries them, merged.

### 5.2 Store A: one file in iCloud Drive *(proposed)*

```
  iCloud Drive / Secrets (the app's own folder, visible in Files)
  ├── My secrets.sgvault             the vault: a zip of bare/, about 20 KB to a few MB
  └── .versions/
      ├── My secrets 2026-11-14T09-12-03Z iPhone.sgvault
      ├── My secrets 2026-11-14T08-40-51Z iPad.sgvault
      └── ...                        the last five, oldest removed
```

- **The container.** The app's own ubiquity container, with `NSUbiquitousContainerIsDocumentScopePublic` so the folder shows in Files and on a Mac's iCloud Drive. It needs the iCloud capability with iCloud Documents and a container identifier registered in the developer portal: an owner step.
- **What the file is.** A zip of the vault's `bare/` folder (compression helps little: the objects are already encrypted), plus a small cleartext header file naming the format and holding the wrapped copies of the vault key (5.6). It is already encrypted object by object; zipping it adds no secrecy and needs none.
- **Writing.** After each commit: build the new zip in a temporary file, then `NSFileCoordinator.coordinate(writingItemAt:options: .forReplacing)` and `FileManager.replaceItemAt` so that iCloud sees one atomic replacement, never a half-written file. Before replacing, move the previous file into `.versions/` and remove the oldest beyond five.
- **Reading.** On launch and on coming to the front: an `NSMetadataQuery` on the container finds the file; if it is not downloaded, `startDownloadingUbiquitousItem(at:)`; read it with a coordinated read; unpack into a temporary folder; treat it as a remote and merge (5.3). While the app is open, an `NSFilePresenter` hears of changes from other devices.
- **Conflicts.** When two devices replaced the file while apart, iCloud keeps one as current and the others as `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`. The app merges each into the current one, writes the result, marks each conflict version resolved and calls `removeOtherVersionsOfItem`. Nothing is chosen by time.
- **Size.** Measured: 31 objects, 17 KB. Estimated, not measured: a change to one secret adds about three small objects (blob, tree, commit), so a few hundred secrets with a few thousand changes is a few megabytes. When it grows, `sgit pack compact` (which exists in the command line) or a Swift equivalent can fold history into fewer objects. A whole-file rewrite of a few megabytes is nothing for iCloud; many small files were the problem the owner remembers, and this avoids it.

### 5.3 Two devices that edited offline *(proposed in Swift; works in sgit today)*

```
   before          iPhone, on a plane           iPad, at home
   ──────          ─────────────────            ─────────────
     O ──────────── A  "Add bank"
      \
       └─────────── B  "Add router"

   back online: iCloud holds two versions of My secrets.sgvault

   1. union the objects:  objects(A-file) ∪ objects(B-file)
                          (a name is a hash, so equal names are equal bytes)
   2. two heads, A and B; their common ancestor O is in both
   3. three-way merge of the trees, path by path:
        only A changed secrets/bank.json     → take A
        only B changed secrets/router.json   → take B
        both changed secrets/wifi.json       → a conflict: keep both, ask
   4. a merge commit M with parents A and B, signed by this device
   5. write M as the new file; resolve the iCloud conflict versions

     O ── A ──┐
      \       M   one file again, nothing lost
       └─ B ──┘
```

Because each secret is its own file, step 3 almost never finds a conflict. When it does, the app keeps both values (one under a conflict name) and shows them side by side with the value both started from, and the person picks. Exactly this ran in sgit 0.27 in this session; in Swift, the merge is the main piece of new engine work (issue 006 lists it among the vault engine's gaps).

### 5.4 Stores B, C and D

| Store | What it is | Written | Read | Status |
|---|---|---|---|---|
| A · iCloud Drive | One file and five past copies in the app's folder | After every change | On open, on coming to the front, on a change notice | Proposed |
| B · This device | The vault folder in Application Support | Always: it is the vault | Always | Unverified (the SGit app keeps vaults this way) |
| C · A copy you keep | The same `.sgvault` file, saved with the share sheet to Files, AirDrop, a USB stick; also a scheduled copy to another folder of the person's choice through a security-scoped bookmark | On request, or after each change if a folder was chosen | Imported and merged like any store | Proposed (the command line reading it is checked) |
| D · SG/Send server | The vault pushed to `dev.send.sgraph.ai` (later production) | After every change, when switched on | On open | Unverified (push and pull built, fast-forward only) |

**Opening a copy on a computer** (checked with sgit-ai 0.27.0):

```
pip install sgit-ai
mkdir vault && cd vault && unzip "../My secrets.sgvault"
sgit clone --transport local --base-url "$PWD" "<vault key>" ../my-secrets
cd ../my-secrets && ls secrets && sgit history log
```

The vault key is shown in the app behind Face ID, or derived from the recovery code (a small `sgit` addition would accept the code directly: proposed). The local transport is read-only: the computer can read and check every signature, and writing back goes through the app or a server.

**The server, if switched on**, adds a browser view and a copy that is not Apple's, and it is the only store that can reach someone outside the person's own Apple account. It is never needed to open, read or change a secret.

### 5.5 Multiple stores, one rule

Every store is a remote; the device's vault is the only working copy. On open the app reads every store it can reach, unions objects, and merges heads, in a fixed order (this device, iCloud, the server, any copy folder). After a change it writes to every store that is switched on, and shows one line per store: "iCloud: saved 09:12", "Server: not switched on", "Copy on USB: last saved 3 days ago". A store that fails is retried and said, never silent; a store that is behind is simply written again.

### 5.6 Who holds the key: custody options

The vault key opens everything, so the design separates **the file** from **the locks that open it**, the way disk encryption keeps several key slots. The file's header holds the vault key wrapped once for each lock the person has set up; any one lock opens it.

| Lock | How it works | What it protects against | What it does not | Status |
|---|---|---|---|---|
| 1. iCloud Keychain | The vault key as a synchronisable Keychain item, as the SGit app keeps it today | Losing one device; nothing to remember; Apple cannot read Keychain items | Someone who takes over the Apple Account and knows a device passcode gets **both the key and the file**: one account is a single point. A synchronised item cannot also demand Face ID | Unverified (SGit app) |
| 2. A passkey | A passkey made for the app; the WebAuthn PRF extension (`ASAuthorizationPublicKeyCredentialPRFAssertionInput`, iOS 18 and later) returns the same 32 bytes for the same passkey and input, after Face ID; HKDF of those bytes wraps the vault key in the header. The same derivation as the passkey door already built | Face ID every time; the passkey can live on a hardware security key or in another passkey manager, **outside the Apple Account**, which breaks the single point above | A passkey in iCloud Keychain is in the same account as lock 1. Needs a relying party domain and associated domains (issue 003). Apple fixed a bug where PRF output differed between local and cross-device use in iOS 18.4 | Derivation built; ceremony proposed |
| 3. A recovery code | 26 base32 characters (128 bits), shown once at setup with a page to print; it wraps the vault key in the header (the door's recovery code path) | Losing every device **and** the Apple Account: the file in any store plus the paper opens it | Whoever finds the paper and a copy of the file has everything. Lost paper is no harm while another lock remains | Derivation built; screens proposed |
| 4. People you trust (later) | Parts of the vault key sealed to three of five confirmed contacts (SGitPeople) | Losing everything, with no paper | Hard to get right; later | Proposed |

**Recommended default:** lock 1 on, so that it "just works" on every Apple device; lock 3 offered at setup and again after the tenth secret, until it is done; lock 2 as the choice for people who want the key away from Apple, ideally on a hardware key. The app always shows which locks exist ("This vault opens with: iCloud Keychain, recovery code").

### 5.7 Threat model, store by store

| Who | Gets | Can read secrets? | Notes |
|---|---|---|---|
| Apple, or a breach of iCloud Drive | The `.sgvault` file and its past copies | No: objects are encrypted with keys from the vault key | Sees size, change times, and that the person uses this app. iCloud Drive is not end-to-end encrypted without Advanced Data Protection; it does not need to be |
| Apple, iCloud Keychain | The vault key, if lock 1 is on | Keychain is end-to-end encrypted; Apple states it cannot read it | The real risk is account takeover plus a device passcode: then file and key together. Lock 2 on a hardware key, with lock 1 off, closes it |
| A thief with an unlocked phone | The app | Only after Face ID or the passcode for each hidden value | The app covers itself in the app switcher (already built) |
| A thief with a locked phone | Nothing usable | No | Data protection classes; the vault folder is encrypted at rest by iOS as well |
| Someone who finds the USB copy | The file | Not without a lock | The same as Apple's position |
| Someone who finds the printed code | A lock | Only with a copy of the file too | Keep the paper away from the computer |
| The SG/Send server, if switched on | The objects and the hash of the write key | No | It can refuse or delete, so it is never the only store. It cannot substitute keys for sharing, because keys come from cards |
| Two devices writing at once | Two versions | n/a | Merged; nothing chosen by time; past copies kept |
| A corrupt or truncated file | One bad version | n/a | Each object checked against its hash before use; the five past copies and every device's own copy remain |

## 6. Sharing and collaboration, later

The pieces are in `SGitPeople` (unverified, on no screen): signed cards as text, a link or a QR code; sealed messages; first contact. Sharing a vault is then: scan or paste the other person's card, seal the vault key (or a read key, for read-only) to their key, drop it in their inbox or hand it over as an `m1.` code. Their copy of the vault needs a store both can reach, and two Apple Accounts do not share an iCloud folder, so a shared vault is where the server (store D), or a shared iCloud folder, becomes useful. A browser session is the same: it gets a card of its own and a sealed read key for a while. None of this is in the first version.

## 7. Names

Checked roughly on 14 November 2026: an App Store search for an app of that name, an obvious trademark, and whether the `.app`, `.ai` or `.com` domain is registered (RDAP lookups; registered means someone holds it, not that it is in use). None of this is a trademark search.

| Name | The case for it | Rough check |
|---|---|---|
| **SGit Secrets** | Says the family and the thing; one product line with SGit Vaults; `secrets.sgit.ai` is already ours as a design page | "Secrets" alone is taken (Outer Corner's Secrets 4, a long-standing Apple password manager), so always with the prefix. Clear |
| **Tinvault** | A tin: small, cheap, yours, kept on a shelf you own. Short, friendly | `tinvault.app` and `tinvault.ai` unregistered; `tinvault.com` registered. No app found |
| **Keyfold** | Every key folded into one small file | `keyfold.ai` unregistered; `.app` and `.com` registered. No app found |
| **Postern** | A small back gate in a castle wall: the door design, and a way out that does not depend on the main gate (our server) | `postern.app` and `.ai` registered; no app found. Obscure word, needs explaining |
| **Pennysafe** | Says the pricing: a safe that costs pennies | `pennysafe.app` unregistered, `.com` registered. "Safe" is a crowded word |
| **Vaultfile** | Says exactly what it is: your vault, as a file | `vaultfile.app` unregistered. Generic, hard to protect |
| **Strongroom** | Solid and British | An App Store app "strong room" (a password manager) exists; `.app` and `.ai` registered. **Clash** |
| **Coffer** | A box for valuables | "Coffre Noir" is a password manager; `coffer.app` and `.ai` registered. Weak |
| **Sealbox** | Sealed, a box | `sealbox.app` registered; "SealPass" is a password manager. Weak |
| **Wicket** | A small door in a larger gate | Apache Wicket is a well-known web framework; `wicket.app` registered. **Clash** |

**Recommended, in order:** **SGit Secrets** (no clash, uses the brand we are building, and says what it is), **Tinvault** (a name of its own if the product should stand apart from sgit; the `.app` and `.ai` are free), **Keyfold** (the file idea in one word). The owner decides; a proper trademark search comes before any public listing.

## 8. A build plan

### 8.1 Shape

A **third app target in this repository**, `Apps/Secrets/` (bundle identifier to be chosen with the name, for example `ai.sgit.secrets.app`), reusing:

- `Packages/SGitVault`: the engine, plus two additions recorded in its `SOURCE.md`: a **file store** (zip a vault folder, unzip into a temporary folder, union two object sets) and a **three-way merge** of two heads with per-path conflicts.
- The SGit Secrets code: `SecretEntry`, `SecretKindOfEntry` and `PasswordMaker` move into a small new local package (`Packages/SGitSecrets`) that both apps use; the screens are adapted to it rather than to `VaultShelf`, which belongs to SGit Vaults.
- `Packages/SGitPeople` later, for sharing.

Adding a target and a package means editing the hand-written Xcode project, which one session at a time may do (CLAUDE.md); a new CI workflow on the pattern of `sgit-app.yml`; a TestFlight group of its own.

### 8.2 Steps, each green in CI before the next

| Step | What | Tested by |
|---|---|---|
| 1 | `SGitSecrets` package: the entry format and password maker moved out of the SGit app, SGit Vaults switched to it, nothing else changed | Its unit tests and the SGit app's, green |
| 2 | The file store in `SGitVault`: zip, unzip, union, atomic replace into a folder, five past copies | Unit tests with temporary folders; the zip written by Swift read by `sgit clone --transport local` in CI (as `sgit_reads_swift.py` does today) |
| 3 | Merge in Swift: common ancestor, three-way tree merge, conflict files, a signed merge commit with two parents | Unit tests; a merge made by Swift checked by `sgit` and a merge made by `sgit` read by Swift, in CI |
| 4 | The app target: one vault, "My secrets", the Secrets screens, Face ID, history of a secret | Unit tests on the CI simulators |
| 5 | Store A: iCloud Drive with `NSFileCoordinator`, `NSMetadataQuery`, `NSFileVersion` conflicts | Unit tests with a folder in iCloud's place; **iCloud itself only on the owner's devices** |
| 6 | Locks: iCloud Keychain (from SGit), the recovery code and its printable page; the key header in the file | Unit tests, the door vectors |
| 7 | Store C: export, a chosen copy folder, import and merge; the command-line instructions in the app | Unit tests; the CI check of step 2 |
| 8 | Credit: the VoiceDebrief ledger and price list, the purchase still switched off until the owner says | Unit tests |
| Later | Lock 2 (passkey PRF, after issue 003), store D (server), AutoFill (an owner step in the portal), import from Apple Passwords, Bitwarden and 1Password CSV or Credential Exchange, sharing through SGitPeople | |

### 8.3 The first version does

One person, on iPhone, iPad and Mac (the Mac as a "designed for iPad" or Catalyst build, as SGit Vaults is). One vault. The ten kinds of secret from SGit, the password maker, Face ID, copy with expiry, the history of each secret. iCloud Drive and the device as stores, with a merge after offline edits and five past copies. Export a copy, and instructions to open it with `sgit`. iCloud Keychain and a printed recovery code as locks. Credit, counted, with no money taken until the purchase is switched on.

### 8.4 The first version does not do

AutoFill in Safari and other apps (until the capability is switched on, the app copies). Storing passkeys. Sharing with another person or a browser. The server. Passkey as a lock. Import from other managers. Android, Windows or a web app. Any model, on the device or elsewhere. Each of these is said in the app where a person would look for it, not hidden.

### 8.5 Owner steps

1. Choose the name and the bundle identifier.
2. In the developer portal: the App ID with iCloud (iCloud Documents, a container), and later AutoFill Credential Provider and an App Group.
3. A TestFlight group.
4. Decide the default locks (recommended above) and the prices (below).

## 9. Pricing

Per use, in the same honesty-box model as VoiceDebrief's [credit](../../credit/index.md): a balance in micro-credits (a penny is 10,000), charged after something is done, never blocking. One rule above all for a secrets manager: **reading, searching, copying and opening a vault are never charged and never blocked**, even below zero, in the way VoiceDebrief never charges or stops a recording. A person must always be able to reach their own passwords.

| What | Placeholder |
|---|---|
| Reading, copying, searching, opening, exporting a copy, the recovery code | Free, always |
| Adding or changing a secret | 1p |
| Merging two devices' changes | Free (it is the app's job) |
| A second or further vault | 10p, as creating a vault in VoiceDebrief |
| Keeping a copy on the SG/Send server (later) | 1p a day while switched on, or per push; to be measured |
| Sharing a vault with a person (later) | 10p |
| Starting credit | £2.00, a placeholder |

Someone who adds or changes twenty secrets a month spends 20p, against £3 to £4 a month for the paid plans in section 3. Top-ups go through the App Store in packs (Apple takes its share, which is one reason for packs and not single pennies); until the owner switches the purchase on, top-ups are simulated, as in VoiceDebrief.

## 10. Questions for the owner

1. **The name**: SGit Secrets, Tinvault or Keyfold, or another?
2. **The default locks**: iCloud Keychain on, the recovery code strongly offered, the passkey optional (recommended), or the passkey as the default?
3. **One file per vault or one file for everything?** Proposed: one file per vault, so that a later shared vault can live in a different store from "My secrets".
4. **Should the first version include the server as an option**, or leave it for later (proposed: later)?
5. **Prices**: are 1p per change and free reading right?

## Sources

- Strongbox on iCloud Drive and duplicates: [Strongbox support: syncing](https://strongbox.reamaze.com/kb/troubleshooting-and-errors/resolve-common-sync-issues), [duplicate copies](https://strongbox.reamaze.com/kb/troubleshooting-and-errors/my-icloud-database-has-numbers-after-it-or-multiple-copies-of-my-database-keep-showing-up-when-i-save); last-writer-wins on iCloud: [PanicVault on sync conflicts](https://www.panicvault.org/cloud-sync/sync-conflicts/).
- Enpass storage and pricing: [PanicVault review](https://www.panicvault.org/password-managers/enpass-review/), [Gaurav Tiwari review](https://gauravtiwari.org/enpass-review).
- Prices: [1Password increase, March 2026](https://vpnoverview.com/news/1password-price-increase-march-27/), [Bitwarden 2026 changes](https://alternativeto.net/news/2026/1/bitwarden-enhances-premium-and-families-plans-with-more-security-features-and-raises-prices), [Proton Pass and 1Password](https://password-manager.cybernews.com/proton-pass-vs-1password/), and the [opportunity brief](../../sgit-app/secrets/opportunity/index.md) for Keeper and Dashlane.
- Apple Account recovery: [Apple Platform Security: recovery contacts](https://support.apple.com/guide/security/secafa525057/web), [recovery key](https://support.apple.com/109345), [recovery contact](https://support.apple.com/en-al/102641).
- Passkey PRF on Apple platforms: [ASAuthorizationPublicKeyCredentialPRFAssertionInput](https://developer.apple.com/documentation/authenticationservices/asauthorizationpublickeycredentialprfassertioninput-swift.struct), [the PRF output bug, fixed in 18.4](https://developer.apple.com/forums/thread/764730).
- Names: App Store listings for [strong room](https://apps.apple.com/us/app/strong-room/id945235429), [Coffre Noir](https://apps.apple.com/us/app/coffre-noir-password-manager/id1473071687), [SealPass](https://apps.apple.com/us/app/sealpass-password-manager/id1573117747), [Secrets 4](https://apps.apple.com/app/id1591056366); domains from rdap.org.
- sgit: sgit-ai 0.27.0 from PyPI, run in this session (`clone --transport local`, `pull` with merge and conflicts).

## Ideas

- **A vault as one file in your iCloud Drive** [[proposed]]: the whole vault is one small encrypted file in the app's iCloud folder, replaced on every change, with five past copies; no server of ours needed.
- **Offline edits on two devices merge** [[proposed]]: two copies of the file join by union of objects and a three-way merge, so nothing is chosen by time and nothing is lost.
- **Several stores at once** [[proposed]]: iCloud Drive, the device, a copy on a USB stick and optionally the server, each a remote, with one line saying when each was last written.
- **Open your vault on any computer** [[proposed]]: the exported file opens with the open `sgit` command (`--transport local`), no app and no account.
- **Locks you can see** [[proposed]]: the vault key wrapped once per lock (iCloud Keychain, a passkey, a printed code), and the app says which locks open it.
- **A passkey on a hardware key as the lock** [[proposed]]: the vault key away from the Apple Account, opened by a security key's PRF.
- **Reading is never charged** [[proposed]]: per-use pricing in pennies where opening and copying your own passwords is always free, even below zero.
