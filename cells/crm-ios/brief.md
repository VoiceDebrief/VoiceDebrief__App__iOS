# Brief: build SGit CRM for iPhone and iPad

For `crm.ios@sgit.dinis`, the builder session of the [SGit CRM cell](README.md), under its [behaviour policy](policy.md).
From the owner, 16 November 2026: "bootstrap the AgenticCell to work on the CRM iOS app that we are going to put on the
Apple Store and use (first) to follow up all the contacts and actions that we have from the Web Summit", and "we need
workflows in the app that allow us to import this data, leveraging vaults to do so".

## Read first

1. `.claude/CLAUDE.md` (the repository's rules: CI is the compiler, reality discipline, working in parallel).
2. `website/built/index.md` (what exists), then `Apps/SGit/` as the pattern for a second app in this repository:
   its own `SGit.xcodeproj`, `SGit.xcconfig`, `sgit-app.yml`, packages wired from `Packages/`.
3. On newsroom.sgit.ai (each page has a `.md` twin): `articles/a-crm-for-us-and-our-agents.md` (the design),
   `articles/the-cell-is-the-unit.md`, `articles/voicedebrief-relaunch.md` (the agent workflows move to this app),
   `articles/the-email-agentic-cell.md`, `articles/the-teams-operating-system.md`, `articles/how-a-vault-works.md`.
4. In VoiceDebrief, what will move here later: `UI/AgentsView.swift`, `UI/InboxView.swift`, `UI/LivePanel.swift`,
   `UI/RecordSidePane.swift`, `Engine/AgentsDesk.swift`, `Model/AgentsReport.swift`, `Engine/DeveloperLane.swift`.

## What to build, in order

Each step is a green `crm-app.yml` run on `work/crm`, with its reality row and a `next` row on the versions page.

1. **The app shell.** `Apps/CRM` with `CRM.xcodeproj`, bundle id `ai.sgit.crm.app`, display name SGit CRM, iPhone and
   iPad (sidebar on iPad), the shared packages wired as SGit Vaults does, a first screen, Swift Testing tests, and
   `crm-app.yml` (build, unit tests on iPhone and iPad simulators; the TestFlight step present but skipped until the
   owner has created the App Store Connect record, decided by a repository variable).
2. **The record format.** A small data model, as JSON files in a vault, one file per record so two devices rarely
   collide: `people/`, `organisations/`, `interactions/`, `introductions/`, `follow-ups/`, `drafts/`, `plays/`.
   Every value carries its source (who or what said it, when, from where). Introductions and drafts are first-class.
   A record changed by an agent says which key changed it. Write the format down as a page on the site
   (`website/crm/format/index.md`) and test it with invented people only.
3. **Import from a vault** (the owner's first workflow). Open a vault by its key or a QR code (as the other apps do),
   find what it holds that looks like contacts (this format; vCard; CSV; JSON lists; photos of business cards and
   badges read on the device with Apple's Vision text recognition), and turn each into a **proposal**: a person, an
   organisation, an interaction, a follow-up, with its source. A review screen shows proposals side by side with any
   existing record they match (a proposed merge), to accept, change or drop, one by one or all at once. Accepted
   records are committed to the user's CRM vault in one signed commit per batch.
4. **Who needs what.** The follow-up pipeline: each person's status, owner, next step and date; a list of what is due,
   overdue, waiting on someone else; introductions to make ("you should talk to this person": who suggested it,
   between whom, why, whether it happened).
5. **Drafts, never sends.** A draft (from an agent, or written here) shown with its source; the person edits it and
   sends it themselves through the system's Mail or Messages compose sheet; the app logs the sent message back as an
   interaction. No code path sends on its own.
6. **Agents propose.** Proposals and drafts arriving on an append lane, sealed to the user's key (the lane code from
   VoiceDebrief and SGitPeople), shown in the same review screen, each with the agent that wrote it.
7. **Then:** the agent workflows from VoiceDebrief (agents, inbox of decisions, live replies), our own fleet of agents
   as records (an agent is a contact, a team an organisation, a lane message an interaction), and the sync to Twenty.

## How to work

- Branch `work/crm`. When green: merge `origin/dev` into it, push, wait for green, then tell the conductor, which lands
  it on `dev`. Never rebase or force-push; never touch `version`.
- `CRM.xcodeproj` is yours; `VoiceDebrief.xcodeproj` and `SGit.xcodeproj` are not.
- The site: a page added updates `website/llms.txt` in the same commit; run `node website/admin/build.mjs` and
  `node website/admin/validate.mjs` before every commit.
- Report to the conductor with `send_message` (session `session_018yvwtN2tecTKQP9tjD8fq6`) at each green step, at any
  blocker, and for any decision that is the owner's. Short, with the run number.
- Style: British English, no em-dashes, plain statements. Apple SDK only. No invented server or model responses in tests.

## Decisions the owner has made

- A third app in this repository (not a new repository), 16 November 2026.
- Name SGit CRM, bundle id `ai.sgit.crm.app`, 16 November 2026. He registers the bundle id and the App Store Connect app.
- Data comes in through import workflows in the app, using vaults.
