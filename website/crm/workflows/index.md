# SGit CRM as workflows made of cells

How SGit CRM is put together, and what it sells: cells, combined into workflows, combined into plays, which together are the CRM. Written 16 November 2026 by the CRM cell (`cells/crm-ios/`) at the owner's request, after the ten workflows mapped for Algarve Evolution ([Ten agentic cells for the death by a thousand cuts](https://algarve-evolution.agenticcells.site/workflows/), a prototype not yet approved by Algarve Evolution). Status: four workflows are built (W1, W3, W5, W12) and the rest are [[proposed]]; each says which.

## The idea in four layers

| Layer | What it is | What a buyer gets | In the app |
|---|---|---|---|
| **Cell** | One unit of work, with its own reach: a piece of code, one model call, an agent's loop, or a person's decision | A part that can be tested alone and reused in other workflows | A Swift type or a lane, with a test |
| **Workflow** | Cells joined end to end, from a trigger to a record, with a policy and a person's approval before anything leaves | One job done the way a person would do it, only faster: "import the summit contacts", "draft a follow-up" | A screen that runs it, and a commit at the end |
| **Play** | A named sequence of workflows the team repeats ("after a conference", "an investor round") | A way of working | A `plays/` record in the vault (the format has them) |
| **The CRM** | The plays, the workflows they use, and the records they leave in the user's vault | The product on the App Store | SGit CRM |

So we do not sell "a CRM" first. We sell workflows, each made of cells we have tested, and the CRM is what you have once you run several of them. A customer can start with one workflow; the AgentiCCells ladder (one agent, a few sessions, a team, a network) says how far it grows.

## Kinds of cell, by altitude

The altitudes of a run (from the Swarm demo of 12 November, in [six setups of an agentic system](https://newsroom.sgit.ai/articles/six-setups-of-an-agentic-system.html)) are the kinds of cell. Each kind has a cost, a reach and a place it may run.

| Altitude | Cell | Example in the CRM | Cost | Where it runs |
|---|---|---|---|---|
| A0 | **Code cell**: plain code, deterministic, tested | the vCard reader, the matcher, the commit | nothing per run | in the app |
| A1 | **On-device model cell**: one call to Apple's models (Vision, the Foundation Models framework) | reading the text on a badge photo | nothing per run; nothing leaves the device | in the app |
| A1 | **Cloud model cell**: one call to Claude, or through OpenRouter | drafting a follow-up in our voice | per call | outside the app, behind a lane: the app holds no API key |
| A2, A3 | **Agent cell**: a loop with tools and a key of its own | merging duplicates, enriching with sources | per run | a Claude session, writing proposals to an append lane |
| P | **Person cell**: a decision only a person may take | accepting a proposal, sending a message | a person's time | in the app |

Cells move down the altitudes as we learn. A job is first done by an agent, because nobody knows its shape yet; once its shape is known, an agent writes it as code, and the code cell replaces the agent cell: fewer moving parts, no cost per run, nothing to reach. The card-text reader is already one: plain rules where a model might have been, tested on invented cards. Every cell keeps the same promise wherever it sits: the policy says what it can reach (the grant), what it was asked to do (the mandate), the difference (the gap) and what stops it (the barriers).

## What every workflow has

As in the Algarve Evolution map: a **trigger** (a vault, a photo, a voice note, a date, a reply); **cells** that read, match and draft; a **policy check**; a **person** who approves anything that leaves or changes a record; a **record** of what changed and which key changed it (one signed commit per batch, in the user's CRM vault). No workflow sends a message: the CRM drafts, a person sends.

## Twelve workflows for the CRM

The first use is the Web Summit 2026 follow-up, so the first workflows are the ones that turn the summit into follow-ups. Times are illustrative estimates for discussion, not measurements.

| # | Workflow | Trigger | Cells | Writes (proposals) | Waits for a person | Time, illustrative | Ladder | Status |
|---|---|---|---|---|---|---|---|---|
| W1 | **Import contacts from a vault** | a vault key or QR code; a vault of vaults such as crm-sources | A0 vault reader, format readers (vCard, CSV, JSON, team CRM layout), matcher, planner, commit; A1 Vision on badge photos; P review | people, organisations, interactions, follow-ups | every proposal, one by one or all at once | 4 hours a list → 20 min | one agent's worth, all in the app | [[unverified]]: built, CI is the test, not tried on a device |
| W2 | **Capture at a stand** | a photo of a badge or card, or ten seconds of voice | A1 Vision; A1 Foundation Models (one question: who, where, what next); A0 matcher; P | a person, an interaction, a follow-up | the proposal | 5 min → 30 s | in the app | [[proposed]] |
| W3 | **Who needs what today** | opening the app; a date | A0 the list: due, overdue, waiting on someone, by owner; P changes a follow-up | a changed follow-up, as a signed commit | every change | 30 min a day → glance | in the app | [[unverified]]: built (step 4), CI is the test, not tried on a device |
| W4 | **Draft a follow-up in our voice** | a follow-up that is due | A1 cloud model behind a lane, or A1 on-device for a short note; A0 template; P edits and sends from the Mail or Messages sheet | a draft; then an interaction once sent | sending, always | 20 min → 3 min a message | one agent | [[proposed]] (step 5) |
| W5 | **Log what was sent and what came back** | the compose sheet closing with Send; later, a reply in the email cell's twin | P sends from the system's Mail or Messages sheet; A0 marks the draft sent and logs an interaction | the draft, sent; an interaction | the person pressing Send | 5 min → 0 | in the app | [[unverified]]: sending and logging built (step 5), CI is the test, not tried on a device; replies are proposed |
| W6 | **Make an introduction** | "you should talk to this person", typed or said | A1 extraction; A0 double opt-in; A1 drafts to each side; P | an introduction; two drafts | asking each side first; every email | 30 min → 5 min | one agent | [[proposed]] |
| W7 | **Debrief a meeting by voice** | a VoiceDebrief note, or a recording in the app | A1 SpeechAnalyzer transcript; A1 Foundation Models, one question at a time; A0 matcher | an interaction, follow-ups, introductions | every proposal | 20 min → 3 min | in the app | [[proposed]] |
| W8 | **Merge duplicates and add sources** | a new batch; weekly | A2 agent proposes merges; A2 a separate agent enriches from public pages, each value with its source; P | changes to people and organisations | every merge; every new value | 3 hours a week → 20 min | a few sessions (two roles, one lane) | [[proposed]] (step 6) |
| W9 | **The team's weekly pipeline** | Monday morning | A0 counts by stage and owner; A1 a short summary; P | none in the CRM; a digest draft | sending the digest | 2 hours → 15 min | one agent, woken by a schedule | [[proposed]] |
| W10 | **Our own fleet as records** | messages on our lanes | A0 lane reader: an agent is a person record, a team an organisation, a lane message an interaction, a hand-over an introduction | people, interactions, introductions | adding an agent the team has not seen | not done today | one agent | [[proposed]] (step 7) |
| W11 | **What the agents are doing** | lanes and the agents vault, while the screen is open | A0 status and messages; A0 the drawing of cells, workflows and who talks to whom; P answers what waits on them | interactions; decisions on a lane | every decision | not done today | starts as a vault app, then native | [[proposed]] |
| W12 | **Exchange keys by QR** | two people, two phones | A0 my contact card as a QR code; A0 scan and check theirs; P confirm it is them; A0 their key on their record in the CRM; next, A0 seal a vault key or a message to it | a person with their key | confirming who they are | 10 min → 30 s | in the app | [[unverified]]: cards and keys built, CI is the test, not tried on a device; sealing to a card is proposed |

Later: the sync to Twenty (an A0 cell, for a classic CRM screen), and the email agentic cell feeding W5.

## Plays that use them

- **After a conference** (the Web Summit play): W1 import every team source, W8 merge, W3 the list, W4 a draft for each, W5 log, W9 the weekly view, until every follow-up is done or parked.
- **At a stand**: W2 for each person met, W6 for each "you should talk to", W7 at the end of the day.
- **Our own team**: W10 every hour, W3 for what each agent is waiting on.

## What the app does today

W1 is built: the cells are `Sources/Import/` (readers, the team CRM layout, vaults of vaults, the matcher, the planner), `CardPhotoReader` (Vision), `Engine/CRMVault.swift` (the signed commit), and the review screen (the person cell). Each cell has its own unit tests on invented people. What the next steps of the brief build fall into W3 (step 4), W4 and W5 (step 5), W8 and W10 (steps 6 and 7). The app's Workflows section lists the twelve with their cells and whether each is built (`Model/CRMWorkflow.swift`), and a test holds it to this page and the [reality file](../../built/index.md): only W1, W3, W5 and W12 are built, every workflow that changes records has a person cell, and no cloud model or agent cell runs in the app.

## Explorers and villagers

A workflow can run as a vault app inside the CRM before it is built into the app, and a switch per section chooses which one runs: see [vaults are the explorers, the app is the villagers](../explorers/index.md).

## What this does not claim

- Only W1 exists, and it has not been run on a device.
- The times are illustrative, for the team to correct, as on the Algarve Evolution page.
- Cloud model and agent cells never run inside the app: the app holds no API key; they write proposals to a lane sealed to the user's key, and the app shows them for a person to accept.
- The layer names (cell, workflow, play) are a proposal for AgentiCCells to take or change.
