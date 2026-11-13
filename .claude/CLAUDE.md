# CLAUDE.md: VoiceDebrief__App__iOS

The single source of truth for anyone, human or agent, working in this repository.

## The product

VoiceDebrief for iPhone and iPad: a voice note in, a transcript and a short debrief out, using
Apple's on-device models only, with the results in an sgit vault the user owns, opened with a
passkey. The plan is `website/plan/index.md`. Load-bearing decisions, not to be casually revisited:

1. **Apple's models only.** `SpeechAnalyzer` for the transcript, the Foundation Models framework for
   the debrief. No OpenRouter, no API key, no inference server.
2. **No backend of ours.** The only server is the sgit vault server, which stores ciphertext.
3. **The passkey is a lock, not an identity.** It opens a door vault; the identity is a key bundle
   generated at random and kept in the master vault. Same design as pki.sgit.ai.
4. **Apple SDK only.** No third-party Swift packages without a written reason.
5. **`dev` is the default branch and it publishes** the site at https://ios.app.voicedebrief.ai.

## Reality discipline

- `website/built/index.md` is the reality file. **If it is not listed there as built, it does not
  exist.** Update it in the same commit as the code it describes.
- The plan is intention. Label anything not built as proposed. Never let the app's own screens
  claim something it does not do (a test enforces this for the status screen).

## Repository rules

- **CI is the compiler.** Swift cannot be built in a Linux container. Push, then read the `ios`
  workflow's job summary (errors are copied there). Do not report Swift work as done until that
  run is green.
- **Never commit secrets**: no vault key, access key, API key or private key. Nothing that decrypts
  what is committed may be committed. `node website/admin/validate.mjs` scans the whole repository
  and CI runs it on every push. The fixture vaults under `Packages/SGitVault/Tests/` are throwaway.
  One thing that looks like a secret is committed on purpose: the developer lane link in
  `DeveloperLane.swift` (a vault id, an append token that can only write, a public key).
- **`Packages/SGitVault` is a copy** from `PrompTugal__App__iOS`. Record every change to it in
  `Packages/SGitVault/SOURCE.md`.
- **The Xcode project is hand-written** with folder-synchronised groups: adding a Swift file needs
  no project edit. Adding a target or a package does. Resource file names must be unique.
- **The site**: each page is `website/<path>/index.md`; run `node website/admin/build.mjs` and
  commit the generated `index.html`. A page added, moved or removed updates `website/llms.txt` in
  the same commit.
- **Releases**: set the next version in `version`, add a row to `website/versions/index.md`, push to
  `dev`. CI tags a version that has no tag yet.
- **Work tracking**: `issues/open/NNN-slug.md` and `issues/done/`, one file each.
- **Style**: British English, no em-dashes, plain statements. Code is Apache 2.0; content CC BY 4.0.
- **Tests**: Swift Testing in the app, XCTest in `SGitVault` (as it came). No invented model or
  server responses: replay recorded real ones.

## Session start

1. This file.
2. `website/built/index.md` (what exists).
3. `issues/open/` (what is next).
4. `website/plan/index.md` for the part you are working on.
