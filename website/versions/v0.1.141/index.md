# What changed in v0.1.141

Released 16 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

SGit CRM, first step: the app shell in `Apps/CRM`, with its own project and workflow (`crm-app.yml`), bundle `ai.sgit.crm.app`, for iPhone and iPad. A sidebar of the places the CRM will have (follow-ups, people, organisations, introductions, drafts, import), each saying it is not built yet and which step builds it. No TestFlight until the App Store Connect record exists.

SGit CRM, second step: the record format, `sgit.ai/crm/v1`. One small JSON file per record in a vault (people, organisations, interactions, introductions, follow-ups, drafts, plays), each value with where it came from, every change saying who made it and an agent always naming its key. Introductions and drafts are records of their own, and only a person can mark a draft sent. [The format](../../crm/format/index.md). Nothing on screen yet.

SGit CRM, third step: import from a vault. The app keeps your CRM in a vault on the device. Import opens another vault by its key or a QR code, finds what looks like contacts (vCards, spreadsheets saved as CSV, JSON lists, CRM records, and photos of business cards and badges, read on the device), and shows each as a proposal, marked when it looks like someone you already have. Accept, change or drop them, one by one or all at once; what you accept is kept in one signed commit, with a note of where you met and a follow-up for each new person if you want them. People and Organisations show what is kept, each detail with where it came from. It also reads the Web Summit team CRM's own layout (contacts, their companies, stages, owners and next steps) and a vault that lists other vaults, such as crm-sources, asking which of them to read; records sealed to the team's keys are listed as not readable yet. Not yet tried on a device.

SGit CRM, how it is put together, at the owner's request: [workflows made of cells](../../crm/workflows/index.md). A cell is one unit of work (code, a call to Apple's models on the device, a call to Claude behind a lane, an agent, or a person's decision); cells make workflows, workflows make plays, plays make the CRM, and workflows are what we sell. Ten workflows for the Web Summit follow-up, after the ten mapped for Algarve Evolution; the first, import from a vault, is built.

SGit CRM: agreed with the email AgenticCell how the CRM will work with its copy of the mailbox (people joined by email address, a small change file per sync, a reference to the CRM's draft carried through to the send result), and the signed lane entries the CRM will propose replies with, checked against the email cell's own test vector. Nothing sends.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
