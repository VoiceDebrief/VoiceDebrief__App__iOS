# 400: SGit CRM, a third app for iPhone and iPad

Opened 16 November 2026, at the owner's request. Status: open, being built by the cell in `cells/crm-ios/`.

A CRM of our own, on vaults, first used to follow up every contact and action from Web Summit 2026 (design:
[A CRM for us and for our agents](https://newsroom.sgit.ai/articles/a-crm-for-us-and-our-agents.html)).
App Store name SGit CRM, bundle id `ai.sgit.crm.app`, code in `Apps/CRM`. The brief is `cells/crm-ios/brief.md`.

## Needs from the owner

- ~~Register the bundle id `ai.sgit.crm.app` and create the SGit CRM app in App Store Connect~~ (done, 16 November).
- For the Gmail inbox (W13): an iOS OAuth client in the Google Cloud project that has the Gmail OAuth app, for bundle `ai.sgit.crm.app`, with `gmail.readonly` and `gmail.send` on its consent screen; its client id is pasted or scanned into the app (not a secret, never committed).

## Done when

The app imports contacts from a vault as proposals, keeps them in the user's CRM vault, lists who needs a follow-up,
and lets a person send a draft themselves, on a device, from TestFlight.

## Progress (16 November 2026, evening)

Green on `work/crm` and handed to the conductor to land: step 1 (the app shell, run 1), steps 2 and 3 (the record
format; import from a vault, including the team CRM layout and crm-sources; run 7, landed in 0c88842), vault apps and a
switch per section (run 9), step 4 (who needs what) and step 5 (drafts, never sends) (run 13 on e6a7964). Also: the
workflows map ([website/crm/workflows/](../../website/crm/workflows/index.md)), the explorers page
([website/crm/explorers/](../../website/crm/explorers/index.md)) and `lane.entry/1` for the email cell. Nothing has been
tried on a device: TestFlight waits on the owner's decision d7. Sealed team records wait on d8.

Next: a first CRM vault app (needs the CRM vault on the server), W11 (what the agents are doing), W12 (exchange keys by
QR), step 6 (agents propose on a lane).

## Progress (17 November 2026)

Sample data, W11 (agents), W12 (cards and keys by QR), the twin reader and the demo vaults are landed, and the app is in
TestFlight (the owner opened it on a device). At the owner's request, W13: a Gmail inbox in the app (sign in with Google,
read, add a sender to the CRM, reply or write, send only after a confirmation), beside the mailbox twin. It waits on the
owner's iOS OAuth client to be tried.
