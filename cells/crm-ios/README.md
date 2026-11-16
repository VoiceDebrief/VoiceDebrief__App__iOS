# Cell: SGit CRM for iPhone and iPad (the team that builds it)

The CRM described in [A CRM for us and for our agents](https://newsroom.sgit.ai/articles/a-crm-for-us-and-our-agents.html),
built as a cell in the sense of [The cell is the unit](https://newsroom.sgit.ai/articles/the-cell-is-the-unit.html):
one focused job, with an objective, a deliverable and a behaviour policy. Started 16 November 2026 at the owner's request.

| | |
|---|---|
| **Objective** | Build SGit CRM, a native app for iPhone and iPad on the App Store, and use it first to follow up every contact and action from Web Summit 2026. |
| **Deliverable** | A green build of `Apps/CRM` on every push to `work/crm`, then on `dev` and in TestFlight, with each step written in `website/built/index.md`. The first usable slice: import contacts from a vault, review them as proposals, see who needs a follow-up, read a draft and send it yourself. |
| **Behaviour policy** | [policy.md](policy.md) |
| **The brief** | [brief.md](brief.md): what to build, in what order, and how to report |
| **Owner** | Dinis Cruz. Decisions go to him through the conductor (the VoiceDebrief app session), as Inbox decisions. |
| **Conductor** | The VoiceDebrief app session (`ios.app.voicedebrief.app`): briefs the cell, lands its green work on `dev`, relays the owner. |

## Parts

- **A Claude session**, the builder: `crm.ios@sgit.dinis`, on the branch `work/crm`.
- **This repository**: `Apps/CRM` with its own `CRM.xcodeproj` (as `Apps/SGit` has), reusing `Packages/SGitVault`, `Packages/SGitPeople` and `Packages/SGitSecrets`.
- **CI**: its own workflow, `crm-app.yml`, modelled on `sgit-app.yml`. CI is the compiler.
- **Vaults**: the CRM's records live in an sgit vault the user owns; contacts come in from vaults (the owner: "workflows in the app that allow us to import this data, leveraging vaults").
- **Lanes and keys**: agents propose records and drafts on append lanes; every change says which key made it.
- **App Store**: the name SGit CRM and the bundle id `ai.sgit.crm.app` (the owner's decision, 16 November 2026). The bundle id and the App Store Connect record are registered by the owner; until then the app builds and tests on simulators without a TestFlight upload.

## Later: the team that uses it

The second cell the article asks for (capture, merge and enrich, plan follow-ups, draft in our voice, with a person sending)
starts once the import and the follow-up list work on a device. Not part of this cell.
