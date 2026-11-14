# 200: People, messages and secrets (the SGitPeople package)

**From:** the owner, 14 November 2026 (the brief in [the article](../../website/articles/people-messages-and-secrets/index.md)).
**Session:** the people session, branch `work/people`.

Every install is a person with keys and an inbox; people meet by exchanging signed cards; everything they send
each other, secrets included, is sealed to the recipient's key and dropped in their inbox. One Swift package,
`Packages/SGitPeople`, used by both apps.

## Done in the package (first slice)

- `PKIKit.swift` and `LaneCrypto.swift` moved in from VoiceDebrief, made public, nothing else changed;
  `pki-interop.yml` compiles them from there.
- `ContactCard`: a pki.sgit.ai statement (`type: card`, `registry: sgit.ai/people`) carrying the name, the
  sgit key bundle and the inbox; as `sgc1.` text (about 1,200 characters for a 4096-bit key), a link, a QR code.
- `ContactBook`: contacts with how each was met; a later card from the same keys updates, other keys under a
  known fingerprint are refused.
- `PeopleMessage`: sealed and signed in sgit's envelope; kinds text, voice-note reference, secret, vault
  invitation, card; `from` and `to` inside the seal are checked on opening. `sgm1.` text for a sealed message
  handed over without an inbox.
- `LaneClient`: write, list, fetch, mark processed, configure, against answers recorded from dev.send.sgraph.ai.
- `InboxCheck` (list, fetch only when something waits, keep on disk, then mark processed), `MessageStore`,
  `InboxSchedule` (on opening and coming to the front, every minute in use, doubling to 15 minutes when idle,
  never in the background), `InboxMaker` (a new vault and its lane).
- `SecretsStore`: Keychain, iCloud Keychain by default with a switch; each secret records who gave it and who
  was given which version; Face ID or the passcode before a value is shown (`SecretsStore.unlock`).
- `FirstContact`: section 5 of the article, the access key sealed to a newcomer's card.

## Next

1. Prove the first-contact round trip against the live server (a throwaway vault, destroyed after).
2. Screens in SGit Vaults: You, Contacts, Inbox, Secrets (with the sgit app session, which owns `Apps/SGit`).
3. VoiceDebrief: its recipients become contacts; the record screen shows the inbox (the parent session's screens).
4. A page on the site for `card/#sgc1…` and `sealed/#sgm1…` links, which shows what it holds and opens nothing.

## Assumed, for the owner to confirm (the article's four decisions)

1. The access key is given in the first exchange (section 5), sealed to the newcomer's card.
2. The card is a new signed statement in pki.sgit.ai's form, compatible with its key bundle.
3. Each person's inbox is a lane on a vault of their own.
4. Publishing to pki.sgit.ai is optional and off by default (nothing publishes yet).

## What the live server showed (14 November 2026)

A wrong append token, a missing or wrong enumeration key, and a vault that does not exist all answer 404 with
an HTML page: the client cannot tell them apart. The `inbox` a list returns is the append token itself, so a
list must never be shown or logged as it comes. Whether configure needs the access key could not be checked
from a cloud session, whose proxy adds it to every request; issue 110's notes say it does.
