# Owner mode and its feed, `owner.feed/v1`

Owner mode is a section of VoiceDebrief for iPhone and iPad meant for one person, the owner. It shows every agent and what it is doing, the latest websites, videos, briefs and decision slides the agents made, and the decisions they need from him. He decides there, and he can talk to any page and have the message relayed to the agent that made it. It is R6 of the brief of 23 November 2026, built by a.ios.

> In test. The section, the contract below and an invented twin are written, and not yet tried on a device. The handshake that makes the mode exist only for the owner's key is [[proposed]] (slice 2). [What is built](../built/index.md) is the record.

## Where the app reads it

| Source | What | Sent anywhere? |
|---|---|---|
| Demo | The twin bundled with the app, [`owner-feed-twin.json`](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/Apps/VoiceDebrief/Resources/owner-feed-twin.json): invented agents, pages and decisions on `example.com` | Never. Answers and messages are kept on the device and marked "Not sent: demo" |
| Live | `owner/feed.json` in the agents vault (the vault the conductor writes `agents/agents.json` into, chosen on the Agents screen) | An answer or a message is sealed to the asking agent's lane, or the conductor's when the agent has none |

The app reads JSON only. It never reads an agent's state from an HTML page.

## The contract

One JSON file. Dates are ISO 8601 in UTC. Fields marked optional may be left out.

```
{
  "kind": "owner.feed/v1",          required, exactly this
  "made": "2026-11-23T18:00:00Z",   when the feed was written
  "by": "holacracy.d",              who wrote it
  "twin": true,                     optional: true for invented data; the app then never sends
  "about": "...",                   optional
  "agents":    [ Agent ],
  "sites":     [ Item ],            optional, each list
  "videos":    [ Item ],
  "briefs":    [ Item ],
  "slides":    [ Item ],
  "decisions": [ Decision ]
}
```

**Agent**: `id`, `name`, `kind` (`maestro`, `agent`, `signer` or `subagent`; the app lists them from the biggest to the smallest), `status` (`working`, `waiting`, `idle`, `blocked`, `done`), `doing` (one line). Optional: `account`, `parent` (an agent id), `waitingFor`, `site` (an address), `statusURL` (where the agent publishes its own state as JSON), `lane` (an `sgi1.` link that can only write to it), `updated`.

**Item** (a site, a video, a brief, a set of slides): `id`, `title`, `url`, `agent` (an agent id), `made`. Optional: `summary`, `seconds` (for a video), `signedBy` (agent ids), `decision` (for slides: the decision they are for).

**Decision**: `id`, `title`, `options` (at least two), `from` (an agent id), `at`. Optional: `detail`, `lane` (where the answer goes; otherwise the conductor), `slides` (an item id), `evidence` (addresses of what it rests on: the brief, the signatures).

The app refuses a feed whose `kind` is different, in which an id is used twice, in which an item or a decision names an agent the feed does not list, or in which a decision has fewer than two choices. The checks are in `OwnerFeed.check()` and its tests.

## What comes back

Each answer or message is one small JSON body, sealed on the device to the receiver's public key and appended to its lane, as every lane message is (see [receiving notes](../conductors/index.md)). The lane header's `kind` is the body's kind.

```
{"kind":"owner.answer/v1","id":"…","at":"…","to":"<agent id>","decision":"<decision id>","choice":"Green","app":"0.1.149 (…)"}
{"kind":"owner.message/v1","id":"…","at":"…","to":"<agent id>","page":"https://…","pageTitle":"…","text":"Make it green","app":"…"}
```

## Decisions apart from actions

The brief asks that the owner's decisions be kept apart from his actions. In the app, "Your decisions" lists answers to questions an agent asked. "Your actions" lists what he did on his own initiative: a message to an agent, or talking to a page. Each record says whether it was sent and to which key.

## What comes next

1. **The handshake** [[proposed]]: the app's own key is registered with the owner's key (issue 018 and the pki.sgit.ai delegation), and owner mode opens only on a device that holds such a grant.
2. **Any agent's decisions** [[proposed]]: decisions from any agent, not only the conductor, answered to that agent's own lane.
3. **Published state** [[proposed]]: the feed built from each agent's own committed JSON (`status.json`), once an index of agents exists.
4. **Talking** [[proposed]]: a chat over the feed with Apple's model on the device, one question at a time through function calls; talking to a page by voice.
5. **The CI pipeline** [[proposed]]: each repository's latest run in the feed.

The work is tracked in [issue 054](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/054-owner-mode.md).
