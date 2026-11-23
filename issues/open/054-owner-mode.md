# 054: Owner mode (R6) and the Sovereign Website exploration (R7)

**Status:** open. Asked for in the brief of 23 November 2026 (R6 and R7), worked on by a.ios (account A) on
`work/owner-mode`. The contract is at `website/owner/index.md`; the R7 exploration at
`website/ideas/sovereign-website/index.md`.

## Slices

1. **Owner section, demo first.** Built and green in CI, not yet tried on a device: `Model/OwnerFeed.swift`,
   `Engine/OwnerDesk.swift`, `UI/OwnerView.swift`, `Resources/owner-feed-twin.json`, `Tests/OwnerFeedTests.swift`.
   The contract `owner.feed/v1`, a demo from an invented twin, live from `owner/feed.json` in the agents vault,
   answers and messages sealed to a lane, decisions and actions kept apart.
2. **The handshake.** Built, not yet compiled by CI: `Model/OwnerHandshake.swift`, the This device section, `tools/owner/grant.py`, `Tests/OwnerHandshakeTests.swift`. Waits for the owner's signing fingerprint to be pinned.
3. **Any agent's decisions**, answered to that agent's own lane. Proposed.
4. **Published state** from each agent's committed JSON, once holacracy.d's index exists. Proposed.
5. **Talking**: a chat over the feed with Apple's model; talking to a page by voice. Proposed.

## Status and debrief

- 23 November 2026, first wake. Read the brief's R4, R6 and R7 (sent by a.maestro; adding the PrompTugal
  repository to this session was refused), the reality file, issues 018 and 019, and `website/develop`. Made
  a.ios's sgit-ai 0.27.0 key; commits on `work/owner-mode` are signed with its ECDSA P-256 half (SSH signing),
  and the public half is in `website/identity/agent-keys.json` and `allowed_signers`. Wrote slice 1 and the R7 page.
- 23 November 2026, later. The first CI run failed in `SGitPeople`'s first-contact tests: their invitations,
  made at the test clock of 14 November, were opened at the real clock and had expired (on every branch, `dev`
  too). Fixed in the tests. `ios` and `People interop` are green on `f7d0e8d`, which already holds `origin/dev`.
  Slice 1 is ready for `dev` the moment the owner says yes.
- 23 November 2026, 18:52 wake. Slice 2, the handshake. `grant.py` run end to end here with a throwaway device key and
  a.ios's key standing in for the owner's; its output is the test fixture. `pinnedOwners` is empty on purpose: the
  owner's fingerprint is his to give (a configuration step, public), and pinning a guessed one would be wrong.
- Not done on purpose: nothing pushed to `dev`. A green push to `dev` uploads to TestFlight, and TestFlight
  submission is the owner's decision.
- The private signing key lives in this session's container only. If the container is replaced, a new key is
  made and added to `agent-keys.json`; the old one stays listed for the commits it signed.

## The owner's actions (not decisions)

- Give his sgit signing fingerprint (`sgit pki list`; public) to be pinned, then grant his iPhone and iPad.

- Create an Apple ID for the account.
- Register The Cyber Boardroom with Apple as a company.
