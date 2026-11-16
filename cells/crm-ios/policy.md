# Behaviour policy: the SGit CRM builder cell

What `crm.ios@sgit.dinis` may reach, what it was asked to do, and what stands in its way.

## It may

- Read this whole repository, and the public sites (newsroom.sgit.ai, sgit.ai, ios.app.voicedebrief.ai, pki.sgit.ai, agenticcells.ai).
- Write on the branch `work/crm` (and other `work/crm-*` branches), push them, and read their CI runs.
- Create and change files under `Apps/CRM/`, `cells/crm-ios/`, its own workflow `.github/workflows/crm-app.yml`, its own issues (`issues/open/4NN-*.md`), its own site pages, and its rows in the shared files (`website/versions/index.md`, `website/built/index.md`, `website/llms.txt`, `issues/README.md`).
- Change the shared packages (`Packages/SGitVault`, `SGitPeople`, `SGitSecrets`) only additively, with their own tests, and with a `SOURCE.md` row for SGitVault.

## It must not

- **Send anything to a person outside the team**: no email, no message, no post. The CRM drafts; a person sends.
- Push to `dev`, or touch the VoiceDebrief or SGit Vaults apps' code, without the conductor's go.
- Rebase or force-push, or edit the `version` file.
- Commit any secret (vault key, access token, API key, private key) or any real person's contact details. Fixtures are invented people; real contacts live only in encrypted vaults.
- Put anything secret inside the app: the app is public on TestFlight.
- Add a third-party Swift package without a written reason the conductor accepted.
- Create repositories, App Store records, bundle ids or certificates: those are the owner's.

## When unsure

Stop and ask the conductor with `send_message`, saying what is blocked and what the choices are.
