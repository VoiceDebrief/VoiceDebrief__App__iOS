# 055: Sites, talking to a Sovereign Website's keeper (R7, tier 1)

**Status:** open. Asked for by the owner through a.maestro, 23 November 2026 (R7 expanded: the Sovereign Website app
for iOS, three tiers). First demo: Thursday 26 November, the owner with the Chiswick Cheese Market team: "do you want
to make a change to the website? Just speak here, and then the agent will come back to you". Worked on by a.ios on
`work/sites` (branched from `work/owner-mode`).

## Tier 1 in VoiceDebrief (this issue)

Scan the site's QR code (a link to its `/send/` page whose `#key=` carries the person's key, issued by the keeper),
see the site in a web view, say what should change (transcribed on the device, or typed), and the request goes to the
keeper sealed and signed exactly as the site's own page sends it. The keeper's answers come back from
`send/replies/<person>.json`, opened on the device, and the screen says when the site has changed.

Built, not yet compiled by CI or tried on a device: `Model/SiteSend.swift`, `Engine/SitesDesk.swift`,
`UI/SitesView.swift`, `Tests/SiteSendTests.swift`.

## What it rests on

- The formats of `site/send/send.js`, `keyring.js` and `inbox.json` of Site__Organisation__Chiswick-Cheese-Market at
  65002f9, relayed verbatim by a.maestro (this session may not read that repository itself).
- The keeper acts only on requests signed by a key in its `requesters.json`: the person key the app holds must be one
  the keeper issued and listed.

## Left

- The keeper's recorded demo request and reply (asked of account C): the tests use keys made in the test until then.
- Which request kinds the keeper expects (the app sends `change`).
- Photos with a request (the format is known: `{name, type, data}`, JPEG at most 1600 px).
- A notice when the app is in the background (today: a banner on the site's screen, and a count on the list).
- Tiers 2 and 3 and the separate app: see `website/ideas/sovereign-website`.

## Status and debrief

- 23 November 2026, evening. Formats, desk, screen and tests written from the relayed files. Asked a.maestro for the
  request kinds. Nothing goes to `dev` until the owner says yes (A4).
