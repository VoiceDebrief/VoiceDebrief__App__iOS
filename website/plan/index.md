# VoiceDebrief for iPhone and iPad: the implementation plan

**Status: the plan.** Nearly everything on this page is proposed and does not exist yet. What does exist is
listed on [What is built](../built/index.md), and that page wins wherever the two disagree. Written 13 November
2026, before the repository existed; the section just below records what has been decided since.

Sources read: `VoiceDebrief__Website` at v0.1.31, `VoiceDebrief__Chrome_Extension__MeetScribe`
at v0.3.5, `PrompTugal__App__iOS` at v0.4.103, sgit.ai (site v0.7.87), pki.sgit.ai (v0.2.33),
newsroom.sgit.ai, and Apple's WWDC26 developer pages. Section 12 lists them.

## Decided since this plan was written

13 November 2026, in the conversation that started the repository:

| Decision | What was decided |
|---|---|
| D7, the repository | `VoiceDebrief/VoiceDebrief__App__iOS`, default branch `dev`, site at `ios.app.voicedebrief.ai` |
| D8, sharing the Swift vault code | `SGitVault` was copied in at a recorded commit; extraction into a shared repository is still to schedule |
| Paying for it | A consumption model on the pattern of newsroom.sgit.ai's SG Meter: £5.00 of starting credit, a few pence per minute of audio debriefed, the balance allowed to go negative, nothing ever blocked, a charge can be declined with a reason. The ledger lives in the user's vault. Top-up is an In-App Purchase of about £5 (Apple does not allow Apple Pay itself for digital credit used inside an app). This replaces "no payment in v1" below: it is its own milestone, after the account and vault |
| D4, Private Cloud Compute | Still an opt-in mode and not in the first build. Confirmed from Apple's session: the same API with one line changed, a 32,768-token context, reasoning levels, no key and no cost to us, a daily limit counted against the user's iCloud account |
| The on-device context | 8,192 tokens on newer devices under iOS 27, not only the 4,096 assumed in section 5.2. Chunking is still needed for older devices and long notes |
| Infographics | Not by image generation: Image Playground is a system sheet only and its code-only API is deprecated in iOS 27. Instead the model produces the content as structured data and the app draws it with native templates. After v1 |

Still open: D1 (the passkey's relying party; this plan assumes `pki.sgit.ai`), D5 (who issues SG/Send access
keys to app users), D6 (keeping the audio in the vault), and the price per minute.

---

## 1. What is being built

A native iPhone and iPad app that does VoiceDebrief's one job (voice note in, transcript and
short debrief out) with **no OpenRouter, no API key and no inference server**: Apple's
on-device speech-to-text does the transcript, Apple Intelligence does the debrief. Results are
kept in an **sgit vault the user owns**, opened with a **passkey** exactly as pki.sgit.ai does
it, and the user has **one identity**: one sgit key bundle (an encryption pair and a signing
pair) that signs what the app produces.

In the product's own vocabulary this is the third privacy mode, the one the web app only has
as a proposal: **device-local**. Audio and transcript never leave the device for inference.
The only thing that leaves is ciphertext, to the vault server, and only once the user has a
vault.

### In scope for v1

| Area | v1 |
|---|---|
| Input | Record in the app; import from Files; receive from the share sheet (WhatsApp `.opus`/`.ogg`, `.m4a`, `.mp3`, `.wav`) |
| Transcript | Apple `SpeechAnalyzer` + `SpeechTranscriber`, on-device, with time ranges |
| Debrief | Apple Foundation Models, on-device: classify, summary in the web app's three sections, optional translation |
| Storage | Local first; an sgit vault as the second home, synced when online |
| Sign-in | One passkey button (signs up and in); recovery code as the second door |
| Identity | One sgit-compatible bundle: RSA-OAEP 4096 + ECDSA P-256; debriefs signed with it |
| Devices | iPhone and iPad, one universal target; the same account on both through iCloud Keychain |

### Not in v1 (labelled so nobody assumes them)

- Infographics (the web step calls an image model; there is no on-device equivalent to rely on).
- Speaker diarization. Apple's speech stack does not provide it; MeetScribe does not have it either.
- Chat over a transcript, personas, web of trust, registering in the pki.sgit.ai register from the app.
- Sealing a debrief to another person's key (milestone 6, after v1).
- Android, Mac Catalyst, watchOS.
- Any payment. With no inference cost there is nothing to bill, which also keeps the app clear of the App Store commission question the strategy brief raised.

---

## 2. Decisions for you

These change the plan if you answer differently. Each has my recommendation, and the plan
below assumes it.

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | Which relying party owns the passkey | **`pki.sgit.ai`** | The same passkey, door, master vault and key bundle as the web register: genuinely one identity. Costs one static file on pki.sgit.ai (section 6.2). The alternative, `voicedebrief.ai`, gives a separate door and a separate identity that would need linking later |
| D2 | How the app writes vaults | **Reuse the `SGitVault` Swift package from `PrompTugal__App__iOS`** and finish what it lacks | A native reader and writer already exists (about 2,500 lines, CryptoKit and CommonCrypto only), with a CI job in which sgit-ai 0.27 reads back what Swift wrote. sgit.ai's "one code base writes vaults" rule argues against a *new* port; this one is already written and tested, so the cost is keeping it in step, not building it (section 6.3) |
| D3 | Minimum OS | **iOS/iPadOS 26.0**, built with the iOS 27 SDK | `SpeechAnalyzer` and Foundation Models both arrive in 26. Passkey PRF needs 18.4 or later for consistent bytes. iOS 27 adds an optional better model (D4) |
| D4 | Apple's Private Cloud Compute model | **Off in v1; a labelled opt-in mode later** | "Only Apple" is still true, but text leaves the device, so it must be a mode the user chooses, never a silent fallback |
| D5 | How a user gets an SG/Send access key | **Works local-only without one; accepts one by paste, QR, or a sealed pki.sgit.ai message** | Creating a vault needs an access token; reading does not. This is the same ladder pki.sgit.ai uses. Who hands out keys to app users is a product question I cannot answer from the repos |
| D6 | Keep the audio in the vault | **Yes by default, with a per-debrief and a global off switch** | MeetScribe's rule: check anything that matters against the audio. A 2-minute Opus note is about 200 KB |
| D7 | Repository | **New repo `VoiceDebrief__App__iOS`**, laid out and built like `PrompTugal__App__iOS` | Follows the family naming (`VoiceDebrief__<Kind>__<Name>`); the website repo's "one repo, three targets" decision would need a line recording the change |
| D8 | How the shared Swift packages are shared | **Copy `SGitVault` and the passkey and Keychain code in at a recorded commit for v1; extract a shared package repo once two apps depend on it** | A copy is the fastest start and the vault team's fixes can be pulled by diff. Two diverging copies is exactly the drift sgit.ai warns about, so the extraction should be scheduled, not left open. You said the new repo is separate; if it turns out to be the PrompTugal monorepo instead, this becomes "add an app to `apps.json`" and D8 disappears |

---

## 3. What already exists, and what does not

Facts the plan rests on, each from a source read for this document.

**The web pipeline (exists).** `website/app/workflows/standard.json` is a state machine:
normalise, ingest, transcribe, classify, translate (only when needed), summary, infographic
(only when asked). All inference is OpenRouter from the browser with the user's own key.
Prompts are markdown files in `website/app/prompts/`. The summary is markdown with exactly
three sections: `## Key points` (3 to 6 bullets), `## Actions` (`- [who] what`, or
`- none mentioned`), `## In one sentence`. Classify returns a validated JSON shape (language
with confidence, up to 5 topics, register, sentiment, urgency, signals, a summary line).
Results are held in memory only; there is no history.

**MeetScribe (exists).** Adds the conventions worth inheriting: transcript lines are
immutable with edits as a revision layer; flags never delete; cost is `null`, never `0`;
exports carry a `format` and `version`; and the standing caveat, "Written by a model, not a
stenographer."

**Vaults, PKI and passkeys in the VoiceDebrief repos: none.** No vault, crypto, key or
WebAuthn code exists in either VoiceDebrief repo. Native apps are an open, unscheduled issue
(011) with no repo name or structure decided. Everything in sections 5 to 7 is built from the
sgit estate, not from VoiceDebrief code.

**The sgit vault format (exists, documented, test-vectored).**

| Piece | Construction |
|---|---|
| Vault key | `<passphrase>:<vault id>`; generated ones are 24 + 8 characters of `[a-z0-9]`; prefixed `sgit_private_vault_` when it leaves the app |
| Read key | PBKDF2-HMAC-SHA256(passphrase, `"sg-vault-v1:" + vault_id`, 600,000, 32 bytes) |
| Write key | PBKDF2-HMAC-SHA256(passphrase, `"sg-vault-v1:write:" + vault_id`, 600,000, 32 bytes) |
| Content | AES-256-GCM, 12-byte IV, 16-byte tag, stored as IV, then ciphertext, then tag |
| Addresses | `ref-pid-muw-` + first 12 hex of HMAC-SHA256(read key, `"sg-vault-v1:file-id:ref:" + vault_id`); branch index likewise with `file-id:branch-index`; objects are `obj-cas-imm-<sha256 of ciphertext>` |
| Server | `https://send.sgraph.ai` (pki.sgit.ai uses `https://dev.send.sgraph.ai`); reads need no auth; writes need `x-sgraph-access-token` and `x-sgraph-vault-write-key`; one commit is one `POST /api/vault/batch/{vault_id}` |
| Publish | `pushIfMatch()` compare-and-swap, merge on `ECAS`, never `push()` |

**The passkey door (exists on newsroom.sgit.ai and pki.sgit.ai).** Exact, from `door.js`:

```
prf input   = SHA-256("<rp>/door/v1")
door seed   = HKDF-SHA256(ikm = prf bytes, salt = SHA-256("<rp>"), info = "sgit/door/v1", 32)
passphrase  = hex(HKDF-SHA256(ikm = seed, salt = empty, info = "sgit/door/v1/passphrase", 32))
vault id    = 8 chars of [a-z0-9] from HKDF-SHA256(seed, empty, "sgit/door/v1/id", 64),
              a byte used only when < 252
recovery    = the same, with the 16 bytes of a 26-character base32 recovery code as the ikm
```

`<rp>` is `pki.sgit.ai` on the register. The chain is passkey to door vault to master vault
to book vault. The master holds the private keys in sgit's key store layout
(`keys/sha256_<fp>/{metadata.json, private_key.pem, public_key.pem, signing_private.pem,
signing_public.pem}`), `identity.json`, `doors.json`, `book.json`, `inbox.json` and
`.vault/access-token.json`. Test vectors checked against sgit's Python are published at
`newsroom.sgit.ai/passkey/vectors.json`.

Two findings from that work that shape this plan:

- **The passkey is a lock, not an identity.** Key pairs are generated at random and stored in
  the master; they are never derived from PRF bytes.
- **One door per path.** The same passkey gave different PRF bytes through the QR (hybrid)
  path than on the device. The design treats an unknown address as "no door here for this
  path yet" and offers the recovery code or adding a door from an open device.

**The key bundle (exists, byte-compatible with `sgit pki`).**

| Piece | Construction |
|---|---|
| Encryption pair | RSA-OAEP 4096, e = 65537, SHA-256 |
| Signing pair | ECDSA P-256 / SHA-256, signatures raw (r then s), 64 bytes |
| Fingerprint | `"sha256:"` + first 16 hex of SHA-256 over the DER SPKI |
| Public bundle | `{ v: 1, encrypt, sign, label, fingerprint, signing_fingerprint }`, keys as PEM |
| Envelope v2 | base64 of `{ v: 2, w, i, c[, s, f] }`: RSA-OAEP wraps a fresh AES-256-GCM key; `s` signs `c` only |
| Detached signature | `<file>.sig` holding `{ signature, fingerprint }`, as `sgit pki sign` writes |

**Swift code that already exists in `PrompTugal__App__iOS` (v0.4.103).** This is the largest
finding of the research, and it removes most of the risk from sections 6 and 7.

| Exists | Where | State |
|---|---|---|
| sgit vault reader and writer | `Packages/SGitVault` (`SGitVault` actor, `VaultCommitBuilder`, `VaultWrite`, `VaultCrypto`, `VaultKey`, `HTTPVaultTransport`, `FolderVaultTransport`) | Reads are live. Writes use one batch with compare-and-swap and per-device branches; proven against sgit's in-memory server and by `sgit` reading them back (`ios-vault.yml`), **never against the live server**, because nobody had an access token |
| The passkey door | `SGitVault/VaultDoor.swift` | The same derivation as `door.js`, with the site constant `web-summit.newsroom.sgit.ai` |
| Account unlock | `VaultAccount.unlock` | Door to master to reader vault, reads `.vault/access-token.json`. **Unlock only**: I found no account creation, no add-a-door, no vault creation with a derived id |
| Passkey with PRF | `PTVaultUI/VaultUnlock.swift` (`PasskeyPRF`) | `ASAuthorizationPlatformPublicKeyCredentialProvider`, RP `promptugal.news`, behind a feature flag |
| Keychain and Face ID | `PTVaultUI` (`VaultKeychain`, `VaultKeyWrap`, `VaultDeviceSigner`) | Keys behind biometrics with a 60-second reuse window |
| sgit hybrid envelope v2 | `PTLanes/LaneCrypto.swift` | RSA-OAEP SHA-256 through the Security framework, SPKI and PKCS#1 conversion, fingerprints. Encrypt and decrypt with imported keys; **I found no RSA key generation and no bundle export** |
| On-device model wrapper | `Apps/RiskMandate/Sources/Workbench/OnDeviceModel.swift` | `SystemLanguageModel` availability mapped to UI text, streaming responses. Its notes record a context of about 4K tokens and English more reliable than Portuguese |
| Dictation | `PTAsk/SpeechDictation.swift` | The older `SFSpeechRecognizer`, live only, audio not kept. Not `SpeechAnalyzer` |
| Not present anywhere | | A share extension, file recording, `SpeechAnalyzer`, three-way merge in the vault writer |

The repo's rules matter as much as its code: Apple SDK only, no third-party packages;
hand-written Xcode projects with folder-synchronised groups; Swift Testing; and "CI is the
compiler", since no agent can build Swift in a Linux container.

**Apple's side.** iOS 26 ships `SpeechAnalyzer` / `SpeechTranscriber` (long-form, on-device,
models downloaded through `AssetInventory`) and the Foundation Models framework
(`LanguageModelSession`, `@Generable` guided generation, `SystemLanguageModel.default.availability`).
Per Apple's WWDC26 pages, iOS 27 adds a language-model protocol so a session can run on other
models, a newer Apple model on Private Cloud Compute at no API cost for apps in the Small
Business Program with under 2 million first-time downloads, and an Evaluations framework for
testing prompts. I found no Apple statement of iOS 27 changes to `SpeechAnalyzer`; treat the
speech API as the iOS 26 one until spike S2 says otherwise.

---

## 4. Architecture

```
 ┌────────────────────────── App (SwiftUI, iPhone + iPad) ──────────────────────────┐
 │  Record · Import · Library · Debrief view · Account · Settings                    │
 └───────────────┬───────────────────────────┬───────────────────────┬──────────────┘
                 │                           │                       │
        ┌────────▼────────┐        ┌─────────▼────────┐     ┌────────▼─────────┐
        │  DebriefPipeline │        │   DebriefStore   │     │    AccountKit    │
        │  (state machine  │        │  local, the      │     │  passkey → door  │
        │   from a JSON    │        │  source of truth │     │  → master → vault│
        │   workflow)      │        │  on this device  │     │  + identity      │
        └──┬─────┬─────┬───┘        └─────────┬────────┘     └───┬─────────┬────┘
           │     │     │                      │                  │         │
   ┌───────▼┐ ┌──▼───┐ ┌▼──────────┐   ┌──────▼──────┐   ┌───────▼──┐ ┌────▼─────┐
   │AudioKit│ │Speech│ │Intelligence│   │  VaultSync  │   │ VaultDoor│ │  PKIKit  │
   │ decode │ │ Kit  │ │    Kit     │   │ queue, CAS, │   │ (in      │ │ RSA-OAEP │
   │ Ogg/   │ │Speech│ │ Foundation │   │ merge       │   │ SGitVault│ │ ECDSA,   │
   │ Opus   │ │Analy-│ │ Models,    │   └──────┬──────┘   │ existing)│ │ bundle,  │
   │        │ │ zer  │ │ Translation│          │          └──────────┘ │ envelope │
   └────────┘ └──────┘ └────────────┘   ┌──────▼──────┐                └──────────┘
                                        │  SGitVault  │
                                        │ (existing   │── copied from PrompTugal__App__iOS,
                                        └─────────────┘   extended: create, doors, merge
```

### 4.1 Packages

Local SwiftPM packages, Apple SDK only, each with a Swift Testing target, following the
PrompTugal rule that packages have no upward edges.

| Package | New or reused | Frameworks | Holds |
|---|---|---|---|
| `VDCore` | new | Foundation | The debrief data model, workflow state machine, prompt loading and filling, classify validation, chunking, the vault file layout. No UI, no I/O: the most heavily tested package |
| `SGitVault` | reused, extended | CryptoKit, CommonCrypto, Compression | Vault read and write, `VaultDoor`, `VaultAccount`. Extended with: create a vault, create with a derived id, create an account, add a door, merge |
| `PKIKit` | new, seeded from `LaneCrypto` | Security, CryptoKit | Key generation, the bundle, fingerprints, PEM and PKCS#8, envelope v2, detached signatures |
| `OggOpus` | new | Foundation | Ogg page and packet parser; format sniffing by magic bytes |
| `AudioKit` | new | AVFoundation, AudioToolbox | Recording to file, decode to PCM, waveform |
| `SpeechKit` | new | Speech | `SpeechAnalyzer` wrapper, model asset management |
| `IntelligenceKit` | new, seeded from `OnDeviceModel` | FoundationModels, Translation, NaturalLanguage | Sessions, guided generation, map-reduce summary, availability |
| `AccountKit` | reused from `PTVaultUI`, reshaped | AuthenticationServices, Security, LocalAuthentication | Passkey ceremony with PRF, Keychain cache, the account state machine |
| `VaultSync` | new | Foundation | The outbox queue, publish, pull, sync state |

`SGitVault` also declares macOS, so its tests run with plain `swift test` on the CI Mac host
without a simulator. Keep that property for `VDCore`, `PKIKit` and `OggOpus`: they are where
most of the logic and all of the interop tests live, and a host test run is minutes faster
than a simulator one.

### 4.2 Privacy posture, stated the way the family states it

- Default and only mode in v1: **device-local**. The app makes no network request during
  record, transcribe or debrief, other than Apple's own model-asset downloads.
- The vault server sees what sgit.ai says it sees: vault id, object sizes, timing, object
  counts. Never filenames, contents or keys.
- No analytics, no telemetry, no third-party SDKs.
- The honest sentence for the UI: "Transcribed and summarised on this device by Apple's
  models. Nothing was sent to us or to anyone else. Written by a model, not a stenographer:
  check anything that matters against the audio."
- The App Store privacy label should come out as "Data Not Collected". Verify at submission.

---

## 5. The pipeline on Apple's models

### 5.1 Stages

The web app's workflow file is reused as a format: `workflow/standard-ios.json`, same schema,
run by a Swift state machine in `VDCore`. Budgets become time ceilings, since nothing costs
money.

| Step | Web today | iOS |
|---|---|---|
| normalise | Sniff the first 64 bytes, relabel | Same logic, ported to `OggOpus`; never trust the extension |
| decode | Remote `sg-audio-decode`, WASM Opus on Safari | `AudioKit`: Ogg demux in Swift, Opus packets through `AVAudioConverter` (`kAudioFormatOpus`); everything else through `AVAudioFile`. Output: the PCM format `SpeechAnalyzer` asks for |
| transcribe | `google/gemini-3.5-flash` | `SpeechAnalyzer` with a `SpeechTranscriber` module, results with audio time ranges |
| classify | LLM, JSON validated against allowlists | Foundation Models guided generation into a `@Generable` struct with the same fields and allowlists; language detection from `NLLanguageRecognizer`, not the model |
| translate | LLM, only when needed | Apple's Translation framework (`TranslationSession`), on-device; same "only when needed" rule and the same 0.75 confidence threshold |
| summary | LLM, three-section markdown | Foundation Models; the same three sections; map-reduce when the transcript does not fit (5.2) |
| infographic | Image model, opt-in | Not in v1 |
| sign | does not exist | ECDSA signature over the debrief and the manifest (section 7) |
| save | does not exist | `DebriefStore`, then `VaultSync` |

Rules carried over unchanged: the transcript is never overwritten by a translation; nothing
from classify is fed back into a prompt; a failed optional step degrades and says so, a
failed transcribe aborts.

### 5.2 The four hard parts

**Language has to be known before transcription.** The web pipeline lets the model work out
the language; `SpeechTranscriber` needs a locale up front. v1: the user's chosen language
(default: device language, remembered per input source) with the choice visible before the
run, and a one-tap "wrong language, run again". After transcription `NLLanguageRecognizer`
checks the text and warns on a mismatch. An automatic guess (transcribe the first 15 seconds
in each of the user's keyboard languages and pick the most confident) is a later improvement
that spike S2 should cost.

**The on-device model's context is small.** The iOS 26 on-device model has a 4,096-token
window for instructions, input and output together. A five-minute voice note can exceed it.
So summary is map-reduce from day one: split the transcript on sentence boundaries into
chunks with a token budget, extract key points and actions per chunk with guided generation,
then merge into the three sections in a final pass. Every bullet keeps the time range of the
chunk it came from, which gives the `[hh:mm:ss]` citations MeetScribe's debrief has. Spike S2
measures the real limits on the iOS 27 model before the chunk size is fixed.

**Not every device or language has the models.** Three independent availabilities, each
checked at launch and before a run, never guessed:

| Check | If missing |
|---|---|
| `SpeechTranscriber` supports the locale, assets installed | Offer the download; if the locale is unsupported, say so and offer `DictationTranscriber` as a lower-quality path |
| `SystemLanguageModel.default.availability` (device not eligible, Apple Intelligence off, model not ready) | Transcript-only mode, stated plainly, with the reason and the Settings link. The app is still useful |
| The model supports the debrief language | Summarise in a supported language and translate with the Translation framework, labelled as translated |

Apple Intelligence needs an iPhone 15 Pro or later, or an iPad with an M-series or A17 Pro
chip. `SpeechTranscriber` reaches more devices. The App Store listing must say what works
where. pt-PT against pt-BR matters to this product: which Portuguese each Apple model
supports is a spike S2 question, not something to assume.

**Guardrails will refuse some real voice notes.** The system model refuses or truncates on
content it classifies as unsafe, and a family voice note about a hospital visit can trip it.
Treat a guardrail error as a degraded step ("Apple's model declined to summarise this. The
transcript is complete."), never as a crash and never retried with altered text.

### 5.3 Prompts and evaluation

- Prompts live as markdown in the app bundle under `Prompts/`, copied from
  `website/app/prompts/` at a recorded commit and then adapted, because a 3-billion-parameter
  model needs shorter and more literal instructions than Gemini. The four locales and their
  tone lines (en-gb, en-us, pt-pt, pt-br) carry over.
- Guided generation replaces "return JSON only" wherever the output is structured.
- A fixed corpus of real voice notes (the user's own, with consent, never committed in
  plaintext; an encrypted vault is where they belong) is run through the pipeline on a device
  and scored: key points present, no invented actions, section format exact. iOS 27's
  Evaluations framework is the intended harness; a plain XCTest runner is the fallback.

---

## 6. Account: passkey, doors, vaults

### 6.1 The flow, identical in shape to pki.sgit.ai

```
 passkey ──PRF──▶ door vault ──holds the key of──▶ master vault ──holds the key of──▶ debriefs vault
 recovery code ─▶ recovery door ──────────────────────┘                └─▶ book vault (pki.sgit.ai's, untouched)
```

1. **One button.** "Continue with a passkey" runs an assertion with the PRF extension and
   the fixed input `SHA-256("pki.sgit.ai/door/v1")`. If the user has no passkey for the site
   it runs a registration (with PRF requested) and then the assertion.
2. **Derive the door** from the 32 PRF bytes (`VaultDoor`, with the site constant made a
   parameter: today it is fixed to `web-summit.newsroom.sgit.ai`).
3. **Look for the door** at its derived address. Three outcomes:
   - *Found*: read `master-key.json`, open the master, read the debriefs vault key, open it.
     The user is signed in, with their identity and their debriefs, on a new device, having
     typed nothing.
   - *Not found, no access key*: the **local account**. The debrief store and the identity
     are kept on the device, encrypted with AES-256-GCM under
     `HKDF(door seed, "voicedebrief.ai/local/v1")`, the same idea as pki.sgit.ai's
     `pki.local.v1` entry. Everything works except sync.
   - *Not found, access key present*: create the master, the debriefs vault and the door;
     write a recovery door; show the recovery code once.
4. **Add the access key later** (paste, QR, or opening a sealed `m1` link from pki.sgit.ai):
   the local account moves into vaults, and the key is stored at `.vault/access-token.json`
   in the master so no other device asks for it again.

The master gains one file, `voicedebrief.json` (`{ v: 1, vault: "<prefixed vault key>" }`).
Nothing pki.sgit.ai wrote is changed, so an existing register account opens in the app and
an account made in the app opens on pki.sgit.ai.

### 6.2 The passkey in a native app

- API: `ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "pki.sgit.ai")`,
  with the `prf` field on the registration and assertion requests (iOS 18 and later).
  `PasskeyPRF` in `PTVaultUI` already does the assertion half for `promptugal.news`;
  registration with PRF is to be added.
- **Requirement on pki.sgit.ai:** an `apple-app-site-association` file at
  `https://pki.sgit.ai/.well-known/apple-app-site-association` listing the app under
  `webcredentials`, and the `webcredentials:pki.sgit.ai` Associated Domains entitlement in
  the app. It is one static JSON file, but it is a change to another site and it makes that
  site vouch for this app, so it needs your sign-off and a note in that site's own record.
- There is no server to issue or verify a challenge. The app generates a random one and
  discards the signature, as the web pages do. The passkey is used as a key-derivation
  device, not for authentication to anyone. Say so in the security notes.
- **User handle.** iCloud Keychain replaces a passkey that has the same user id for the same
  site. The app must always try an assertion first and only register when there is none,
  and a registration must use a fresh random user id.
- **Same bytes as Safari?** Expected yes: same credential, same input, platform path, iOS
  18.4 or later. Apple's engineers have said the values should match. I could not find it
  confirmed for the native API against Safari, so it is spike S1. If they differ, nothing
  breaks: the design already calls that "another path, another door", added once from the
  recovery code or from an open device.
- **Third-party password managers** (1Password, Google Password Manager on iOS) may not
  return PRF bytes through the native API. On no PRF output the app says which store
  answered and offers the ladder: use iCloud Keychain, or use the recovery code.
- The door seed is cached in the Keychain (`WhenUnlockedThisDeviceOnly`, biometric access
  control) so opening the app is Face ID, not a passkey sheet every time. Signing out
  deletes it.

### 6.3 Writing vaults (D2)

Reuse `SGitVault`. What has to be added to it, in order:

| Gap | Why the app needs it | Notes |
|---|---|---|
| Live writes proven | Everything | Run the existing write tests against `dev.send.sgraph.ai` with a real access token. This is spike S3 and needs a token from you. Until it passes, vault sync is unproven, not merely unfinished |
| Create a vault | First device | There is no create endpoint: the first batch creates the vault and the server remembers the hash of the write key. First commit, named ref, clone ref and branch index in one batch |
| Create with a derived id | Doors | The door's id and passphrase come from the PRF bytes, not from random |
| `createAccount`, `addDoor` | Sign-up, recovery door, second path | Port of `newsroom-vault.js`, about 60 lines of JavaScript, with the same file names |
| Merge | Two devices | With the layout in 6.4 every device only adds new folders, so a file-level merge that takes both sides and reports a conflict only on a same-path change is enough. Full three-way content merge is not needed for v1 |
| Presigned upload | Audio over 4 MB | Long recordings only; can follow v1 if "keep audio" is capped |

Three rules from sgit.ai's write-up that the Swift writer must keep, each with a test: never
move the named ref unconditionally; refs are never cached while `-imm-` objects always are;
and read the ref once after create, not before every publish, or compare-and-swap silently
becomes overwrite.

**Keeping in step with the format.** The interop job (`ios-vault.yml`) comes across with the
package and is extended to run in both directions and on a weekly schedule against the
newest `sgit-ai` release, so a format change is noticed the week it lands rather than when a
user's vault fails to open. The alternative, running the pinned JavaScript library in a
hidden web view, stays on the shelf as the fallback if the format moves faster than the Swift
writer can follow.

### 6.4 The debriefs vault layout

```
/README.md
/.vault-settings.json                      (the library's)
/debriefs/2026/11/13/<id>/
    manifest.json                          format "voicedebrief/debrief", version 1
    audio.opus                             the original bytes, unless switched off
    transcript.json                        lines with startMs, endMs, text, flags
    transcript.md
    debrief.md                             the three sections
    translation.md                         only when one was made
    manifest.json.sig                      { signature, fingerprint }
/devices/<device id>.json                  label, model, app version, first seen
/index/<device id>.jsonl                   one line per debrief this device wrote
```

- `<id>` is a time-sortable id made on the device. A debrief folder is written once, as one
  commit, so two devices never edit the same file and merges are fast-forwards or trivially
  clean. Edits (a corrected transcript line, a retitled debrief) are new files in an
  `edits/` subfolder, MeetScribe's revision-layer rule.
- Totals and the library list are recomputed from the records, never stored, as the
  newsroom's reader vault does.
- Each device commits to its own clone branch (`ios-<8 chars>`), as sgit.ai requires.
- `manifest.json` carries: id, created, device, source (recorded, imported, shared),
  duration, locale, the classify facts, the SHA-256 of every sibling file, the engine and
  model identifiers with OS version, per-step durations, and `costUsd: null`.
- Because it is an ordinary vault, `sgit clone <vault key>` on a laptop and the vault
  browser at dev.vault.sgraph.ai both open it. That is acceptance test number one.

### 6.5 Sync

Local first. `DebriefStore` is the source of truth on the device; `VaultSync` is a queue.

- A finished debrief is queued, written as one commit, then published with compare-and-swap.
  On `ECAS`: merge, publish again.
- Pull on app foreground and on pull-to-refresh. Refs are never cached; `-imm-` objects are
  cached forever on disk, keyed by id.
- Uploads continue in a background `URLSession` where the engine allows it; otherwise they
  resume on next foreground. Audio over 4 MB goes through the presigned upload path.
- The UI shows, per debrief, one of: on this device only, queued, in the vault.

---

## 7. Identity: one bundle

"One identity" in v1 means exactly one sgit key bundle per account, with role `master`. No
personas.

- **Create.** RSA-OAEP 4096 and ECDSA P-256, generated on the device at account creation.
  RSA-4096 generation takes seconds on a phone: run it off the main actor with a visible
  step, and start it while the user reads the recovery code.
- **Or adopt.** If the master already holds a key (the user made one on pki.sgit.ai), the
  app uses it and generates nothing.
- **Or import.** Two private PEMs and a passphrase from an existing `sgit pki` key store,
  with the public bundle recomputed rather than trusted.
- **Where it lives.** In the master vault, in sgit's key store layout, private halves as
  plain PKCS#8 inside the encrypted vault, exactly as pki.sgit.ai stores them. A copy sits in
  the Keychain behind Face ID for offline use. The Secure Enclave is deliberately not used:
  it cannot hold RSA keys or export anything, and this identity has to be the same on the
  iPhone and the iPad.
- **What the app does with it in v1.**
  - Signs every debrief: a detached signature over `manifest.json`, which holds the hashes
    of the other files. `sgit pki verify manifest.json manifest.json.sig` checks it.
  - Shows the identity: label, both fingerprints, a QR code of the `k1` key link, and "copy
    public bundle".
  - Opens a sealed message addressed to it, which is how an access key arrives (D5).
- **What exists and what does not.** `LaneCrypto` already does the envelope, fingerprints and
  the SPKI conversions with imported keys. To add: RSA-4096 and P-256 generation
  (`SecKeyCreateRandomKey`, CryptoKit), PKCS#8 export and import, the bundle JSON, the key
  store files, detached signatures, and reading sgit's passphrase-encrypted private keys
  (PBES2 with PBKDF2-HMAC-SHA256 and AES-256-CBC, through CommonCrypto).
- **Milestone 6, after v1.** Seal a debrief to a contact's bundle (envelope v2) and hand it
  over as a link or file. When that is built, sign the whole envelope, not only `c`:
  sgit.ai documents that today's signature covers the ciphertext alone.
- **Out of scope.** Publishing to the register. That is a reviewed commit on pki.sgit.ai,
  and the app can export the submission JSON for it without doing more.

---

## 8. The app

### 8.1 Screens

| Screen | iPhone | iPad |
|---|---|---|
| Library | List by day, search over titles and transcripts | Sidebar of a `NavigationSplitView` |
| Record | One large button, live waveform, elapsed time, language shown | Same, in the detail column |
| Debrief | Tabs: Debrief, Transcript, Details. Audio scrubber; tapping a line or a `[hh:mm:ss]` seeks | Debrief and transcript side by side |
| Run progress | The workflow steps with live status, as the web trace shows them | Same |
| Account | Signed-in state, identity card, doors, recovery code, access key, sync state | Same |
| Settings | Language and tone, keep audio, models and their download state, about, licences | Same |

### 8.2 Ways in

- **Share extension.** WhatsApp: hold a voice note, Share, VoiceDebrief. The extension only
  copies the file into the App Group container and opens the app; all processing happens in
  the app, because extensions have a tight memory limit and the models are large.
- **Files and drag and drop** (iPad especially), **"Open in"** for the audio types.
- **App Intents.** "Debrief this voice note" as a Shortcuts action and a share-sheet action;
  "Start a voice debrief" for the Action button and Siri.
- **Live recording** with `AVAudioEngine`, transcribed as it is spoken (volatile results
  shown grey, final results black), so the transcript is done when the user stops.

### 8.3 Conventions

SwiftUI, Swift 6 language mode with strict concurrency, `@Observable` models, no third-party
UI dependencies. British English, no em-dashes, the family's status words. Dynamic Type,
VoiceOver labels on every control, and the transcript is real text, so it is selectable and
readable by assistive technology. Localised in en-GB, en-US, pt-PT and pt-BR from the start.

---

## 9. Repository, CI and delivery

### 9.1 Layout

```
VoiceDebrief__App__iOS/
  Apps/VoiceDebrief/
    VoiceDebrief.xcodeproj          hand-written, folder-synchronised groups
    VoiceDebrief.xcconfig
    Sources/{App,Model,UI}/
    Resources/                      Assets, PrivacyInfo.xcprivacy, Prompts/, Workflows/
    Share/                          the share extension target
    Intents/                        App Intents
    Tests/  UITests/
  Packages/{VDCore,SGitVault,PKIKit,OggOpus,AudioKit,SpeechKit,IntelligenceKit,AccountKit,VaultSync}/
  apps.json                         the package graph, checked on Linux by check_apps.py
  scripts/{apps,release,testflight,vault}/
  .github/{workflows,scripts}/
  website/                          the app's pages, llms.txt, release records
  briefs/  team/  issues/
  VERSION  CHANGELOG.md  LICENSE  .claude/CLAUDE.md
```

Start from PrompTugal's **Fringe** app, the newest and simplest project there (iOS 26.0, one
app target and one test target, empty entitlements), then add the share extension, the App
Group and the associated domain. Two traps recorded in that repo: resources are copied flat
into the bundle, so two files with the same name break the build; and the Keychain is per
bundle id, so the bundle id chosen now is the one to keep.

Suggested identifiers: bundle `ai.voicedebrief.app`, with `.share`, `.intents`, `.tests`,
`.uitests`; App Group `group.ai.voicedebrief.app`. Targets `1,2` (iPhone and iPad).

### 9.2 CI, carried over

Agents work in Linux containers and cannot compile Swift, so CI is the compiler and the
pipeline from `PrompTugal__App__iOS` is the proven way to work like that. Bring across:

| Workflow | What it does |
|---|---|
| `ios.yml` | Linux jobs plan and gate; **one** macOS job (`macos-26`) builds for the generic simulator unsigned, runs package tests on the host, then iPhone and iPad simulator tests one at a time; on a green `dev` push it archives, signs and uploads to TestFlight |
| `ios-vault.yml` | Swift writes vaults on macOS; `sgit-ai` on Linux clones and verifies them. Extend to both directions, to PKI (`sgit pki` import, encrypt, decrypt, sign, verify), and to a weekly schedule |
| `screens.yml` | One XCUITest per screen, driven by launch arguments with sample data; PNG artefacts for iPhone and iPad. This is how an agent sees its own UI |
| `testflight-ops.yml`, `ios-submit.yml` | App Store Connect operations and manual review submission |
| `website.yml` | Version bump, tag, deploy the site |

Lessons already paid for there, to keep: one Mac job per push (the macOS pool is five jobs
and queue time was about three times run time); never boot a simulator while compiling;
build for `generic/platform=iOS Simulator`; `run-and-summarize.sh` copies `error:` lines into
the job summary so an agent can read a failure through the Actions API; archive unsigned and
codesign afterwards, because automatic signing created a certificate per run and hit the
account limit.

**What CI cannot do, and who does it.** No simulator has Apple Intelligence models, a
microphone worth testing, or a passkey in iCloud Keychain. So:

- Logic is tested in CI against protocols: a scripted `Transcriber` and `LanguageModel`
  replaying recorded real outputs (MeetScribe's "replayed real responses" rule), a folder
  vault transport, an in-memory secret store.
- Speech, the model, the passkey and the share sheet are tested **on a device by you**,
  from TestFlight, against a written checklist per milestone. The app has a hidden
  diagnostics screen that runs the evaluation corpus and the spike measurements and exports
  the results as one JSON file, so a device run produces evidence an agent can read.

### 9.3 What only you can do

- Create the App Store Connect record and the bundle id (the API cannot).
- Add the secrets to the new repo's `testflight` environment: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8_BASE64`, `APPLE_TEAM_ID`.
- Enable the capabilities on the app id: Associated Domains, App Groups.
- Publish the association file on the relying party's domain (D1).
- Supply an SG/Send access token for the live write tests, as a CI secret, never in the repo.
- Run the device checklists.

### 9.4 Conventions inherited from the VoiceDebrief repos

`VERSION` owned by CI; `dev` publishes; a reality document where anything not listed does not
exist; briefs folder read-only for agents; issues-fs-lite under `issues/`; CHANGELOG with an
Unreleased heading; `llms.txt` updated in the same commit as any public page; docs CC BY 4.0
and code Apache 2.0; British English and no em-dashes. One conflict to settle on day one:
the website repo says tests use no mocks, the iOS repo uses stubs. For this app the rule
should be MeetScribe's: no invented responses, only replayed real ones.

---

## 10. Milestones

Durations assume one human with agents, as in the sibling repos. Each milestone ends with
something that runs on a device in TestFlight.

### M0. Spikes (week 1). Nothing else starts until these report

| Spike | Question | Done when |
|---|---|---|
| S1 | Does a native app with RP `pki.sgit.ai` get PRF bytes, and are they the bytes Safari gets for the same passkey, on iPhone and iPad? | A test build prints a fingerprint of the bytes beside the pki.sgit.ai login page's on two devices. Needs the association file live (or a throwaway domain first) |
| S2 | What do Apple's models actually do on real voice notes? Locales (pt-PT in particular), accuracy on WhatsApp Opus, context limits, guardrail refusals, time per minute of audio, on the oldest supported device | A table of measurements from ten real notes, and a go or no-go on debrief quality |
| S3 | Do `SGitVault`'s writes work against the live server, and does `sgit clone` read them? | The existing write tests green against `dev.send.sgraph.ai` with a real access token. Needs the token |
| S4 | Does Ogg Opus from WhatsApp decode through `AVAudioConverter`, including odd files (forwarded notes, long ones, stereo)? | Twenty real files decode to the same sample count as `opusdec`; if not, bundle libopus |

S1 decides D1 and S3 confirms D2. S2 decides whether the product is worth shipping at all on
Apple's models alone, so it runs first.

### M1. Repository and the key bundle (weeks 1 to 2, parallel with the spikes)

The repo skeleton from 9.1 with CI green on an empty app, `SGitVault` copied in with its
tests and interop job passing unchanged, and `PKIKit`. Done when:

- A dev push produces a TestFlight build.
- `VaultDoor`, parameterised by site constant, reproduces every value in
  `newsroom.sgit.ai/passkey/vectors.json`, including the deterministic door record
  ciphertext and its object id.
- The interop job passes in both directions: a bundle made in Swift imports with
  `sgit pki import`; a file sealed by `sgit pki encrypt` opens in Swift and the reverse; a
  Swift signature passes `sgit pki verify` and the reverse; an sgit passphrase-protected key
  store imports in Swift.
- Fingerprints match pki.sgit.ai's `keys.js` for its five published fixture identities.

### M2. Transcript on a device (weeks 2 to 3)

Record, import, share extension, decode, `SpeechKit`, the transcript view with audio
seeking, `DebriefStore` local only. No account. Done when a WhatsApp voice note shared to
the app becomes a time-aligned transcript with the phone in aeroplane mode.

### M3. The debrief (weeks 3 to 4)

`IntelligenceKit`: classify, translate, map-reduce summary, the workflow runner and its
progress view, the three availability checks and transcript-only mode, the evaluation corpus
and runner. Done when the corpus passes the format checks and you have read ten debriefs and
judged them usable.

### M4. Account and vault (weeks 4 to 6)

`AccountKit`, the `SGitVault` additions from 6.3, `VaultSync`, the local account and the move
into vaults, recovery code, identity creation and adoption, signing. Done when:

- A debrief made on the iPhone appears on the iPad after a passkey gesture and nothing else.
- `sgit clone` opens the debriefs vault and `sgit pki verify` passes on a manifest.
- An account made on pki.sgit.ai opens in the app with its existing key, and the reverse.
- Deleting the app and reinstalling restores everything from the passkey; with the passkey
  gone, the recovery code does.

### M5. Hardening and release (weeks 6 to 8)

iPad layouts, App Intents, accessibility pass, localisation, security review (section 11),
the site pages and `llms.txt`, App Store review notes that explain the passkey (reviewers
need a path that does not require an access key: the local account is that path), TestFlight
beta, then submission.

### M6. After v1

Seal a debrief to a person; the Private Cloud Compute mode (D4); automatic language guess;
import of MeetScribe's `meetscribe/meeting` JSON; opening a debrief on voicedebrief.ai from
the vault with a read key.

---

## 11. Risks and the security review

| Risk | Likelihood | What the plan does about it |
|---|---|---|
| Debrief quality from the on-device model is not good enough | Real | S2 runs first and can stop the project; transcript-only is still a product; D4 is the upgrade path |
| The language the user needs is not supported | Real for pt-PT | S2 measures it; the summarise-then-translate path; the listing says what is supported |
| Native PRF bytes differ from Safari's | Low | The design already handles a new path; the recovery code bridges |
| Live vault writes from Swift fail in ways the in-memory server did not show | Medium | S3 in week 1, before anything is built on it |
| The vault format changes under the app | Medium | The interop job runs weekly against the newest `sgit-ai`; the web-view engine is the fallback |
| Two copies of `SGitVault` drift apart | High if left alone | D8: a recorded source commit, and a scheduled extraction into a shared repo |
| Nothing can be tested on a device by an agent | Certain | Protocol seams with replayed real outputs in CI; a diagnostics export from device runs; your checklist per milestone |
| A user loses both the passkey and the recovery code | Certain, eventually | Stated at creation, as sgit states it: there is no reset. The recovery code screen cannot be skipped without an explicit "I understand" |
| App Review questions the passkey with no server, or the associated domain | Medium | Review notes; a demo path through the local account |
| Access keys do not scale past a beta | Certain | D5 is a product decision; the app does not depend on the answer to be useful |
| Apple's models change between OS releases and debriefs change with them | Certain | The manifest records OS and model identifiers; the evaluation corpus runs on every OS beta |

**For the AppSec review before M5 closes:**

- Keys in memory: the master's contents exist only while unlocked; zeroed on background
  after a timeout; never logged; no key-shaped string in any crash report or analytics
  (there are none).
- The passkey ceremony verifies nothing (there is no server): confirm that nothing in the
  app treats a successful assertion as proof of anything except possession of the PRF bytes.
- Vault content is untrusted input. A debrief written by another device is rendered as text
  and markdown, never as HTML with scripts.
- The ciphertext rule from the website repo applies to this one: no vault key, access key or
  private key in the repository, with a pre-commit and CI scanner from the first commit
  rather than later (the website's issue 013 is still open on this).
- Test fixtures use published fixture keys only (pki.sgit.ai publishes five).
- File protection `completeUnlessOpen` on the local store; the App Group container holds a
  shared file only until the app picks it up.
- Third-party code: none, by the iOS repo's rule. libopus is the one possible exception
  (spike S4), and it would need a written reason.
- RSA through the Security framework means hand-written DER for SPKI and PKCS#8. That code
  is small and exactly where parsing bugs live: fuzz it, and test it against sgit's files.

---

## 12. Sources

Repositories (local clones): `VoiceDebrief__Website` v0.1.31 (reality doc, brief v0.33.53,
`website/app/`), `VoiceDebrief__Chrome_Extension__MeetScribe` v0.3.5, `PrompTugal__App__iOS`
v0.4.103.

sgit estate:

- https://sgit.ai/security/index.html (the crypto stack, the two key systems)
- https://sgit.ai/docs/pki.html (key bundle, envelope v2, what the signature covers)
- https://sgit.ai/docs/vault/vault-from-javascript.html (one code base; create, write, publish)
- https://sgit.ai/docs/vault/reading-a-vault-file.html (address derivation, untrusted content)
- https://sgit.ai/api/index.html, `/api/vault-objects.html`, `/api/authentication.html`
- https://pki.sgit.ai/llms.txt, `/assets/people/door.js`, `keys.js`, `account.js`
- https://pki.sgit.ai/articles/a-login-made-of-a-passkey.html
- https://pki.sgit.ai/articles/in-person-by-qr-code.html
- https://newsroom.sgit.ai/articles/the-passkey-opens-the-vault.html
- https://newsroom.sgit.ai/admin/notes/2026-10-12__one-door-per-passkey-path.md
- https://newsroom.sgit.ai/passkey/vectors.json
- https://newsroom.sgit.ai/articles/how-a-vault-works.html
- https://newsroom.sgit.ai/articles/a-key-for-every-person.html
- https://newsroom.sgit.ai/articles/meetscribe.html

Apple:

- https://developer.apple.com/machine-learning/whats-new
- https://developer.apple.com/wwdc26/guides/ios/
- https://developer.apple.com/documentation/authenticationservices/supporting-passkeys
- https://developer.apple.com/forums/thread/764730 (PRF output across platform and hybrid paths)

**What I could not verify and have marked as spikes rather than facts:** native-app PRF
bytes matching Safari's (S1); the iOS 27 model's context size, languages and quality (S2);
whether `SpeechAnalyzer` changed in iOS 27 (S2); live vault writes from Swift (S3);
`AVAudioConverter` on WhatsApp's Ogg Opus (S4). The 4,096-token figure and the device eligibility list are the iOS 26 values.
