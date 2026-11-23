# A Sovereign Website app for iPhone and iPad: an exploration

An exploration, not a plan: nothing on this page is built. It is R7 of the brief of 23 November 2026. The question: can a phone edit a simple website with Apple's on-device model ("change this website to green"), perhaps create one, and keep it where its owner wants (published somewhere easy, or on the device, or in iCloud as a zip)? And, in the owner's words, "how can we remove pieces of the puzzle?"

> [[proposed]] throughout. A new repository for it goes only through the chain of evidence in R4 of the brief (a maestro's signed brief, a sites review, the factory, security and abp sign-offs, the decisions agent), and a.maestro files that request. This repository does not create one.

## Now a project: three tiers (23 November 2026)

The owner widened this on 23 November: "quite a powerful capability ... solves a ton of problems from usability point of view ... running models locally, so you have proper sovereignty". iOS first, Android later. a.ios owns it.

1. **Feedback on a site that exists.** Scan the site's QR code, see the site, speak or type what should change; the site's keeper (an agent) makes the change and answers; the app says when the site has changed. Being built inside VoiceDebrief as Sites ([issue 055](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/055-sites.md)), on the site's own `/send/` formats, for a first demo on 26 November.
2. **Edits made on the device with Apple Intelligence**, then either sent back for the keeper to publish, or pushed to the person's own GitHub with the app walking them through it. [[proposed]]
3. **A site from scratch**: photos and one of our themes, helped by a frontier model where it is worth it. [[proposed]]

Across all three: the site kept in iCloud as one file, shared and published from there; publishing to Netlify and other hosts; voice throughout; public testing through TestFlight. A separate app's repository still goes through R4.

## What already exists to build on

- **Lab L07, edit with Apple Intelligence** (in this app, [[unverified]]): a text goes to the on-device model with an instruction and comes back changed, with the change shown. A website is a few small text files, so this is the same move on more than one file.
- **The model door** (`LabModelDoor.swift`): every request to the model goes through one place, with a policy saying which tools it may call and a record of what happened. This is how an edit stays explainable.
- **Vaults** (this app, [[unverified]] on a device): a folder with history, signed commits and push and pull. A website kept in a vault has every version, and undo is a checkout.
- **A vault as one file** (`VaultArchive`): one file that can sit in iCloud Drive or be shared. This is "keep it as a zip", with history.

## The smallest version that would answer the question

1. A site is a folder of at most a few files: `index.html`, `style.css`, and perhaps `site.json` holding the words and colours.
2. The model is never asked to rewrite HTML. It is offered a few tools: `setColour(role, value)`, `setText(id, text)`, `addSection(title, text)`, `removeSection(id)`. The code applies them to `site.json` and renders the HTML from a template. "Change this website to green" becomes one or two tool calls that can be checked and undone, not a wall of rewritten markup. That follows this project's standing position: the code owns the states, and the model is asked one question at a time, through function calls.
3. A preview in a `WKWebView` reads the files from the device. Nothing leaves the device.
4. Every edit is a commit in a local vault, so "if it mucks up" is answered by going back one commit.

The thing to measure is how often the on-device model picks the right tool with the right value for ordinary requests, recorded as Lab runs are, from real requests.

## Where it can live

| Where | What it takes | Pieces removed |
|---|---|---|
| On the device | Nothing: a vault in the app's folder | No server, no account |
| iCloud Drive, as one file | `VaultArchive` written to the app's iCloud container | No server of ours; Apple holds ciphertext if the vault is encrypted |
| A vault server | Push, as the app already does | The server stores ciphertext; a published copy is a separate, plain step |
| GitHub Pages, Netlify and others | A token for that service, kept in the Keychain, and a publish step | Easy hosting; the service sees the plain site, which is the point of publishing |

"Remove pieces of the puzzle", read literally: the smallest set is the phone, the model on it, and a file. Publishing is the one step that needs anybody else.

## If Apple's model is not enough

The owner raised it: "then we might need to put OpenRouter key or other models in there". This app's rule is Apple's models only (decision 1 in the project's instructions), so a second model would be a separate app or a decision to change that rule, which is the owner's. The model door is the place it would plug in: one more door, shown as such, with its own policy.

## Open questions for the owner

- Edit only, or create as well? Creating from a sentence asks far more of a small model than changing a colour.
- Which publisher first, if any? Each one is a connector, and connectors are the owner's decision.
- The same app as VoiceDebrief (a Lab experiment first) or a new one? A Lab experiment needs no repository and could be tried in days; a new app goes through R4.

This page is listed with the other [ideas](../index.md).
