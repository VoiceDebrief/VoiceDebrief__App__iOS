# VoiceDebrief for iPhone and iPad

A voice note in, a transcript and a short debrief out, on the device. The app is being built to do VoiceDebrief's one job with **Apple's own models and nothing else**: no OpenRouter, no API key, no inference server. What it produces is kept in an **encrypted vault the user owns**, opened with a **passkey**, and signed with the user's own key.

> **In development. There is no public build.** A test build records or opens a voice note, transcribes it and writes a debrief on the device, so that Apple's models can be judged on real notes. It keeps notes on the device and can save one to a vault. It has no account. Nobody has judged the results yet. [What is built](built/index.md) is the honest list.

## What it will do

| Step | How | Status |
|---|---|---|
| Bring a voice note | Record in the app or choose a file: in test. Sharing from WhatsApp and its `.opus` files: proposed | [[unverified]] |
| Transcript | Apple's `SpeechAnalyzer`, on the device, with the time of every line | [[unverified]] |
| Debrief | Apple Intelligence, on the device: key points, actions, one sentence | [[unverified]] |
| Keep it | An sgit vault the user owns, encrypted before anything leaves the device. Creating a vault and saving a debrief into it: in test | [[unverified]] |
| Sign in | One passkey, the same account as [pki.sgit.ai](https://pki.sgit.ai), and a recovery code | [[proposed]] |
| One identity | One key bundle (RSA-OAEP 4096 and ECDSA P-256) that signs every debrief | [[proposed]] |

## What exists today

| | | Status |
|---|---|---|
| The app | An iPhone and iPad app, built, tested and delivered to TestFlight by CI | [[built]] |
| The vault engine | `SGitVault`: reads and writes sgit vaults and derives a passkey's door, with tests against published vectors | [[built]] |
| CI | Every push is compiled and tested on a Mac; the vault engine's output is read back by `sgit` | [[built]] |
| This site | Built from markdown, validated, and published from the `dev` branch | [[built]] |

## Where your audio will go

**Nowhere, for transcription and the debrief.** Both run on the device with Apple's models. That is the design, and it is why the app needs no key and no account with us.

**One exception, and only when you press it.** The test build can send a single note (its audio, transcript and debrief) to the developer, to help judge the models. It happens only when the button is pressed, and the note is encrypted on the device to the developer's key before it leaves.

**Your vault is the one thing that leaves the device, and it leaves encrypted.** Files are encrypted on the device before upload, with keys derived from a vault key the server never sees. The server can see the vault's identifier, the size of each encrypted object and when it was written. It cannot see file names, contents or keys. [sgit's security model](https://sgit.ai/security/index.html) states this precisely.

The transcript and debrief are in a test build and have not yet been judged on a real device. Creating a vault and saving a debrief into it have each been done once from the test build, on a Mac. This page will say so when either changes.

## The record

- [How it works](architecture/index.md): the architecture in four drawings, with what is working, what is unconfirmed and what is only decided.
- [What is built](built/index.md): the reality file. If it is not listed there, it does not exist.
- [The plan](plan/index.md): the pipeline, the account, the vault, the identity, milestones and risks.
- [Build and test](develop/index.md): how the repository works and how CI stands in for a Mac.
- [Release history](versions/index.md)
- [Source on GitHub](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS)

Part of [voicedebrief.ai](https://voicedebrief.ai), alongside [MeetScribe](https://meetscribe.chrome-extension.voicedebrief.ai) for Google Meet.
