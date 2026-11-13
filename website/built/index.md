# What is built

The reality file for this repository. **If it is not listed here as built, it does not exist.** The [plan](../plan/index.md) describes intentions; this page describes facts, and it is updated in the same commit as the code it describes.

Status words, as the VoiceDebrief family uses them: [[built]] is in the repository and tested; [[unverified]] is written but has not yet been proven by a run; [[proposed]] does not exist.

## Built

| What | Where | How it is tested |
|---|---|---|
| The app skeleton [[built]] | `Apps/VoiceDebrief/`: a universal iPhone and iPad target, iOS 26.0, SwiftUI, bundle `ai.voicedebrief.app` | Unit tests in `Apps/VoiceDebrief/Tests/`, run by CI on an iPhone and an iPad simulator |
| Capture without loss [[unverified]] | `Engine/NoteStore.swift`, `VoiceRecorder.swift`, `Model/WAVRepair.swift`, `Engine/AudioCompressor.swift`: a note is written to the library when recording starts; the recording goes straight into the note's folder as 16 kHz WAV; a recording that was never closed has its header repaired when the library next opens; an interruption (a call, another app) ends the recording and keeps it; the WAV is replaced by a small `.m4a` only after the note is finished and the copy reads back at the same length | Unit tests: the note exists before the audio, a cut-off WAV is repaired on reopen, the repair's arithmetic, the compressed copy taking the recording's place. On 13 November 2026, build 0.1.7 (12): two notes of 76 and 67 seconds, one of them on an iPad, were recorded, processed, compressed (about 4.4 KB a second) and sent over the lane with their hashes intact. The ordinary path works. The crash, the interruption and the locked screen have not been tried |
| Library on the device [[unverified]] | `UI/LibraryView.swift`, `NoteDetailView.swift`: notes by day, newest first; a note reopened, run again in the language chosen now, or deleted from the device | Unit tests: the store survives a reopen, titles, states and grouping. Notes made in build 0.1.7 on two devices were kept and opened; reopening after a restart, running again and deleting have not been reported |
| The shell [[unverified]] | `UI/RootView.swift`, `RecordView.swift`, `SettingsView.swift`: four tabs that become a sidebar on wide screens; one large record control pinned at the bottom; stopping opens the note, which fills in; diagnostics, the lane and the engine's log under Settings | Used by the owner on two devices in build 0.1.7, who liked the flow and found one fault: the record screen did not follow the live words once they passed the bottom. It now scrolls with them (not yet confirmed) |
| Record or open a voice note [[unverified]] | `Engine/VoiceRecorder.swift`, `DebriefView`: record to a temporary `.m4a`, or choose an audio file. `.m4a`, `.mp3` and `.wav`; not WhatsApp's Ogg Opus | Recording worked in the same first run on a Mac. Choosing a file has not been tried |
| Transcript on the device [[unverified]] | `Engine/SpeechFileTranscriber.swift`: `SpeechAnalyzer` with a `SpeechTranscriber`, the model downloaded on first use, one line per phrase with its time. The language is chosen before the run | First real run, 13 November 2026, build 0.1.1 (5) on an Apple silicon Mac: a 22.6-second English note recorded in the app was transcribed in 0.6 seconds, two lines, accurate bar small slips. One note, one language, one device: not yet a judgement |
| Debrief on the device [[unverified]] | `Engine/OnDeviceModel.swift`, `DebriefSession`: Apple's Foundation Models, the three-section prompt from voicedebrief.ai, a long note read in parts sized from the model's reported context and merged. A refusal or a missing model leaves the transcript standing | The chunking, prompts and format check have unit tests. The model's output has none. On a Mac with Apple Intelligence switched off the app said so and kept the transcript, as designed. First debrief, 13 November 2026, build 0.1.1 (5) on an iPhone: a short English note came back with the three headings and nothing invented, though it turned "let's see if we recorded fine" into an action. A second, one-line note on a Mac showed the model's habits: quotation marks copied from the prompt, a renamed heading (which the app flagged), the note repeated back as a key point. The prompt was changed for 0.1.2 and notes under 25 words are no longer summarised. Long notes and Portuguese are untried |
| Live text and a level display while recording [[unverified]] | `Engine/LiveTranscriber.swift`: the microphone through `AVAudioEngine` into a second `SpeechAnalyzer` with the progressive preset, shown as it changes; bars from the recorder's meter. A preview only: the kept transcript is still made from the recorded file | Compiles in CI; the level mapping has a unit test. The owner has recorded with it on a Mac in build 0.1.5 and called the new flow improved; In build 0.1.7 the owner saw the words appear, grey while unsettled and black once settled. If it cannot start the recording carries on and says why |
| Send a note to the developer [[built]] | `Engine/DeveloperLane.swift`, `LaneCrypto.swift` (copied from `PrompTugal__App__iOS`): with an `sgi1.` lane link pasted in, a button after a run sends the audio in parts and the run as JSON to an sgit append lane on `dev.send.sgraph.ai`, each message encrypted to the link's RSA key with sgit's hybrid envelope. A lane is built into the test build (a vault id, a write-only token and a public key, committed on purpose); a pasted link takes its place. Nothing is sent without the button | Unit tests: the link, the parts, the message format, and a round trip through the encryption with a throwaway key. First note sent and received, 13 November 2026, build 0.1.5 (10) on a Mac: the audio (187 KB, one part, hash intact) and the run arrived, were decrypted by the developer session and matched what the app showed |
| Create a vault [[built]] | `Packages/SGitVault/Sources/SGitVault/VaultCreate.swift`: a random key (24 and 8 characters, as sgit generates them) or a given one; an empty tree, one signed commit, the branch `current` at its derived address, the branch index. No clone branch | Unit tests against a folder; `ios-vault.yml` has `sgit` clone the vault Swift created and verify its signatures; and on 13 November 2026 the owner created a vault from the app on a Mac (build 0.1.5) on `dev.send.sgraph.ai`, which the app then read back with its signature verified |
| Vaults in the app [[unverified]] | `Engine/VaultBook.swift`, `SecretStore.swift`, `UI/VaultsView.swift`: the access token, vault keys and the commit-signing key in the Keychain (this device only); create, add by key, forget; head, files, history, branches; a file fetched and decrypted when opened; the engine's traffic log | Unit tests with an in-memory store: token, signing key, the folder a debrief becomes. Nothing here has run on a device |
| Save a debrief to a vault [[built]] | `VaultBook.save`: `debriefs/YYYY/MM/DD/<id>/` with `debrief.md`, `transcript.md`, `run.json` and the audio (up to 3.8 MB), one signed commit on `current` | The file layout has a unit test. First save, 13 November 2026, build 0.1.5 on a Mac: 4 files in one signed commit (12 objects, 192.5 KB) on the live server, pulled back with the signature verified |
| Diagnostics [[unverified]] | `DiagnosticsView`: speech languages, model status, context size and languages, the last run's timings; exported as JSON without the words of the transcript or debrief | The export's "no words" rule has a unit test |
| The About screen [[built]] | `StatusView`: what the build holds, what is in test and what does not exist, the version, links | The list it shows is checked by tests: the transcript and debrief may not be called built before they are proven |
| The vault engine [[built]] | `Packages/SGitVault/`, copied from `PrompTugal__App__iOS` (see `SOURCE.md` there): read and write sgit vaults, key derivation, the passkey door, account unlock | Its own tests on the CI Mac, against fixture vaults and vectors generated by sgit's Python |
| A door on any site [[built]] | `VaultDoor.door(fromSecret:site:)`: the derivation of `door.js` with the site constant as a parameter, and `VaultDoor.pkiSite` | The vector published at `newsroom.sgit.ai/passkey/vectors.json`: passphrase, vault id, read key and write key |
| The build pipeline [[built]] | `.github/workflows/ios.yml`: the vault tests, a simulator build, a Release device build, unit tests on iPhone and iPad | It is the test |
| TestFlight upload [[built]] | `scripts/release/testflight.sh` and the last step of `ios.yml`: on a green push to `dev` that touches the app, archive unsigned, sign, and upload with automatic signing | Run 4 of `ios.yml` (13 November 2026) uploaded 0.1.0 (4) and App Store Connect accepted it. The owner installed it from TestFlight on an iPhone the same day and it opened |
| Vault interop [[built]] | `.github/workflows/ios-vault.yml`: Swift writes vaults, `sgit-ai` clones and verifies them; on changes to the write path and weekly | It is the test |
| The site [[built]] | `website/`: markdown pages, a builder and a gate with no dependencies | `node website/admin/validate.mjs`: pages current, links, no key-shaped strings, house style |

## Not built

Most of what a user would call the product.

| What | Status |
|---|---|
| Receiving a voice note from the share sheet (WhatsApp) | [[proposed]] |
| Decoding WhatsApp's Ogg Opus | [[proposed]] |
| Recording with the screen locked or the app in the background: the audio background mode is declared | [[unverified]]: never tried |
| Playing a note's audio; tapping a transcript line to hear it | [[proposed]] |
| Several lanes with names; saved and sent states on a note; saving to a vault automatically | [[proposed]] |
| Apple's larger model on Private Cloud Compute, as an option | [[proposed]]: needs the entitlement from Apple and the iOS 27 SDK in CI |
| Translation, classification, citations of time in the debrief | [[proposed]] |
| The passkey ceremony, the account, the recovery code | [[proposed]] |
| Creating an account, adding a door, merge, audio over 3.8 MB in a vault | [[proposed]] |
| The key bundle (`PKIKit`) and signed debriefs | [[proposed]] |
| Saving a debrief, sync between devices | [[proposed]] |
| The share extension, App Intents | [[proposed]] |
| Credit, charging per minute, top-up | [[proposed]] |
| The App Store | [[proposed]] |

## Known limits of what is built

- **Live vault writes from Swift work; `sgit` has not yet opened an app-made vault from the live server.** On 13 November 2026 the app created a vault on the live server and saved a debrief into it (a commit to an existing branch, with compare-and-swap), reading both back with signatures verified. In CI `sgit` clones a Swift-created vault from a folder. Cloning the live one with `sgit` on a computer is the remaining check.
- **An iPad works, and reports a larger model.** A note recorded on an iPad on 13 November 2026 (build 0.1.7) was transcribed and debriefed; the model there reported a context of 8,192 tokens, against 4,096 on the iPhone and the Mac.
- **A long note works.** 6 minutes 44 seconds on an iPad (build 0.1.7): 65 lines transcribed in 5.4 seconds; the whole transcript fitted the iPad's 8,192-token model in one request and the debrief took 10.5 seconds, with six fair key points. The audio was 1.7 MB and crossed the lane intact in one part. Reading in parts has still never run on a device.
- **The debrief loses the thread on a rambling note.** Of the two longer notes, one debrief was fair and the other garbled a spoken aside into an action ("refresh app whenever movement, sub, sub, sub, or focus gain occurs") and gave a task to "[Claude]" because the note addressed Claude by name. The transcripts were good.
- **Installed, not yet judged.** Build 0.1.0 (4) was installed from TestFlight on an iPhone and on an Apple silicon Mac and opened on both. The transcript and debrief arrive in the next build, and whether Apple's models are good enough on real voice notes is the open question of the whole project.
- **The model's language may not match the note's.** The debrief is asked for in the language that was transcribed. Whether Apple's model writes European Portuguese well, or at all, is not known.
- **The four spikes in the plan have not been run**: passkey bytes in a native app, the quality of Apple's models on real voice notes, live vault writes, and Ogg Opus decoding. Each can change the plan.

## Open work

Tracked as files under [`issues/`](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/tree/dev/issues) in the repository.
