# Vaults are the explorers, the app is the villagers

How SGit CRM grows without waiting for app builds. Written 16 November 2026 by the CRM cell at the owner's request. Status: the first part (vault apps inside the CRM, and a switch per section) is [[unverified]]: built, CI is the test, not yet tried on a device. Everything after it is [[proposed]].

## Why

A change to the native app takes half an hour or more to reach a phone (build, test, TestFlight). That is right for what is stable, and too slow for what we are still learning. And the CRM must also work without the app: on a website, opened directly, inside other apps, fed by feeds and append lanes.

So the CRM has two layers, in the explorers, villagers and town planners sense:

| Layer | Where it runs | What it holds | How it changes |
|---|---|---|---|
| **Explorers** | a vault's own app (HTML and JavaScript in the vault), opened inside the CRM in the web Vault, or on its own anywhere | experiments, labs, new workflows, data inputs, feeds, views we are still designing | a commit to the vault: live in seconds, no app build |
| **Villagers** | the native iOS app | what has settled: import, the record format, people, the review screen, signing | an app build, TestFlight |
| **Town planners** | shared packages and formats (`sgit.ai/crm/v1`, `lane.entry/1`, SGitVault) | what everything else stands on | rarely, with versions |

A feature starts as an explorer and moves into the app when it has earned it. **A switch per section** chooses which one you use, so both can live side by side while the native one catches up, and an experiment can replace a native screen for a day without a release.

## What is built

- **Vault apps** (`Apps/CRM/Sources/Vault/`): add a vault by its key, pasted or scanned as a QR code; its key goes to the Keychain, its name and id to settings. Open it full screen inside the CRM: its own app, or its files (the web Vault's embed protocol, copied from SGit Vaults: the key is posted to the page, never put in the address, and the page keeps nothing).
- **The switch** (`VaultApps`, "Where each section runs"): Follow-ups, People, Organisations, Introductions, Drafts and Import can each run natively or from a chosen vault app.
- **A vault as a QR code**: its read key by default (whoever scans it can open it, not change it); the full key only when asked, with that said on the screen.
- Unit tests: adding, switching, reading back after a restart, removing (the key leaves the Keychain), the QR's read key, refusals. Not tried on a device; no vault app for the CRM has been written yet.

## What comes next, in order

1. **A first CRM vault app**: the follow-up list (W3) as HTML in a vault, reading the CRM's own record format, so W3 is an explorer first and native later. Needs the CRM vault on the server (it is on the device only today), or a copy of its records in a vault there.
2. **What the agents are doing** (W11): who is working, waiting or stuck, what they say to each other, what waits on you, drawn as cells and workflows. It starts as a vault app reading the agents vault and the lanes (the same data VoiceDebrief's Agents and Live panels use), then moves into the app.
3. **Keys and QR codes between people** (W12, the card exchange now built; sealing to a card next): my contact card (my public keys, from SGitPeople, as SGit Vaults has it) as a QR code; scan theirs, check its signature, confirm it is them; then seal a vault key or a message to their key. This is how a CRM vault, or a single record, is shared, and how the sealed team records could be opened (Inbox decision d8).
4. **The bridge**: a vault app may ask the native app for a few things through the embed protocol (the person's name, a contact to open, a proposal to review), each one named and shown, never the keys.

## What this does not claim

- The web Vault reads vaults on the server. The CRM's own vault is on the device only, so it cannot be opened as a vault app yet.
- A vault app runs whatever its vault holds: add only vaults you trust, as you would install an app.
- Switching a section to a vault app hides the native screen for that section; the records are the same.
