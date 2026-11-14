# 105: "Send to vault" from Photos and Files (a share extension)

**Status:** open. The plan, written before any code. Owner of the code: the sgit app session.

## What it is

In Photos, Files or any app's share sheet, an entry "sgit": choose a vault and a folder, and the items go in. It is the shortest road from a camera roll to a team's vault.

## How it has to work

A share extension is a separate small program with little memory (about 120 MB) and a short life. It cannot encrypt a video and upload it. So:

1. **The extension only takes the files in.** It copies each item, file to file, into a folder that the extension and the app both own (an App Group container), with a small record: which vault, which folder, the names. Then it closes. This is the same "copy it in before anything else" rule the outbox already follows.
2. **The app does the rest.** When the app is next opened it finds those records and turns each into an outbox job, exactly as if the files had been picked in the app. The extension says so plainly: "Kept. Open sgit to send them."
3. **The extension never holds a key.** It is given only the names and ids of the vaults, which the app writes into the shared folder. Vault keys and the access key stay in the app's Keychain.

What it will not do at first: upload without the app being opened. That needs background uploads (the next item in issue 103), which fits on top of this: the staged ciphertext handed to a background transfer.

## What it changes outside the code

- **A second target** in `Apps/SGit/SGit.xcodeproj` (the sgit app's own project file), bundle id `ai.sgit.vaults.app.share`.
- **An App Group**, `group.ai.sgit.vaults.app`, in the entitlements of the app and of the extension. The outbox's intake folder moves into it.
- **Signing.** Today the release script signs one app with one entitlements file. With an extension it must sign the extension first, with its own entitlements, then the app. `scripts/release/testflight.sh` is shared with VoiceDebrief, so the sgit app gets its own copy.

## The risk, and how it is contained

A mistake in signing does not show until the upload, and the upload only happens on `dev`: a broken extension would stop every sgit app build reaching TestFlight, at the moment the team is using it. So the work is done on its own branch with one extra CI step that archives and signs for distribution without uploading. Nothing lands on `dev` until that step is green.

## What may be needed from the owner

Automatic signing should register the App Group and the extension's identifier by itself (the API key has the Admin role). If it does not, two things in the Apple Developer account, under Identifiers: an App Group `group.ai.sgit.vaults.app`, and an App ID `ai.sgit.vaults.app.share` with App Groups switched on, and App Groups switched on for `ai.sgit.vaults.app`. The signing step's log will say which, and this issue will be updated with exactly what it asked for.

## Steps

1. The App Group and the shared intake folder, with the app reading it on opening. No extension yet. Tests: a record left in the folder becomes a job.
2. The signing dry run in CI, on the branch, with the App Group entitlement alone. This is the step that may need the owner.
3. The extension target: a small SwiftUI screen (vault, folder, a list of what is being kept), copying file to file.
4. Pictures of it through the screens workflow is not possible (an extension cannot be launched alone by a UI test); a device is the test.
