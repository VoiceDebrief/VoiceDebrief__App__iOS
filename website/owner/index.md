# Owner mode and its feed, `owner.feed/v1`

Owner mode is a section of VoiceDebrief for iPhone and iPad meant for one person, the owner. It shows every agent and what it is doing, the latest websites, videos, briefs and decision slides the agents made, and the decisions they need from him. He decides there, and he can talk to any page and have the message relayed to the agent that made it. It is R6 of the brief of 23 November 2026, built by a.ios.

> In test. The section, the contract below, an invented twin and the handshake are written and pass CI, and have not been tried on a device. No owner key is pinned yet, so no grant is accepted until the owner gives his signing fingerprint. [What is built](../built/index.md) is the record.

## Where the app reads it

Three sources, chosen at the top of the Owner screen: **Demo** (the invented twin), **Published** (public feeds in this shape, read as they are: today account D's team index by d.holacracy), and **Your vault** (`owner/feed.json` in the agents vault, after the handshake).

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

Optional fields a feed may also carry, as d.holacracy's team index does: on an agent `circle`, `lead`, `model`, `home` (a repository) and `homeUrl`, `repo`, `session`, `relayed` (reported, not seen), `proposed`; on a decision `recommended` (an option's letter, or several, "AB"); at the top `extra_fields` and `reported_not_seen` (`id`, `name`, `account`, `kind`, `session`, `source`, `as_of`). Dates may leave out seconds.

The app refuses only a feed whose `kind` is different. Anything else that is wrong costs a row, never the feed, and is listed under the feed as what was wrong: a row it cannot read, an id used twice (the first is kept), a decision with fewer than two choices (left out), an item or decision from an agent the feed does not list (kept). The rules are in `OwnerFeed.decode` and `tidy()` and their tests, which include a recorded part of the team index.

### Asked of feed writers

- Name a decision's asker (`from`) and an item's agent by an id from `agents`, so the app can show who it is and reach them.
- Keep ids unique; give a decision's `lane` as an `sgi1.` link when the asker has one, so the answer goes to it and not through the conductor.
- Write full times with seconds (`2026-11-23T17:10:00Z`); the app reads shorter ones, other readers may not.

## What comes back

Each answer or message is one small JSON body, sealed on the device to the receiver's public key and appended to its lane, as every lane message is (see [receiving notes](../conductors/index.md)). The lane header's `kind` is the body's kind.

```
{"kind":"owner.answer/v1","id":"…","at":"…","to":"<agent id>","decision":"<decision id>","choice":"Green","app":"0.1.149 (…)"}
{"kind":"owner.message/v1","id":"…","at":"…","to":"<agent id>","page":"https://…","pageTitle":"…","text":"Make it green","app":"…"}
```

## The handshake: only the owner's devices

Demo works on any device. Live data and sending open only on a device whose key the owner has registered with his own sgit key:

1. **The request.** On the device: Owner, This device, Make a registration request. It is `or1.<json>.<signature>`: the JSON (`owner.request/v1`) names this install's device key (issue 018: a P-256 key in the Secure Enclave, wiped on reinstall) and the device's name, and that key signs it. Shown as a QR code, with Share and Copy.
2. **The grant.** On the owner's own machine, with his key in sgit's key store:

   ```
   pip install sgit-ai==0.27.0
   python3 tools/owner/grant.py --fingerprint <your key, from sgit pki list> 'or1....'
   ```

   The script checks that the device key signed the request, shows what it will grant and asks, writes `owner.grant/v1` (the app, the device key's fingerprint, the request's hash, the owner's signing fingerprint, the time), signs that file with stock `sgit pki sign`, and prints `og1.<envelope>`: the grant's bytes, its `.sig` and the owner's public bundle from `sgit pki export`. The private key never leaves sgit.
3. **The check.** On the device: paste the `og1.` text and Accept. The app accepts it only when the `.sig` is the bundle's signing key's over those exact bytes, the bundle is sound, its signing fingerprint is one the build pins as the owner's (`OwnerHandshake.pinnedOwners`), and the grant names this app and this device's key. A grant for another device, or for this device before a reinstall, is refused.

Nothing in a request, a grant or a bundle is secret. What makes a grant the owner's is the pinned fingerprint and the private key only he holds. The tests check a grant made by the script with stock sgit, and refuse a changed one, an unpinned key and another device.

## Decisions apart from actions

The brief asks that the owner's decisions be kept apart from his actions. In the app, "Your decisions" lists answers to questions an agent asked. "Your actions" lists what he did on his own initiative: a message to an agent, or talking to a page. Each record says whether it was sent and to which key.

## What comes next

1. **The owner's fingerprint pinned** [[proposed]]: the owner gives his public signing fingerprint, it goes into `OwnerHandshake.pinnedOwners`, and a build carrying it accepts his grants. Later, a grant may also come through the pki.sgit.ai delegation.
2. **Any agent's decisions** [[proposed]]: decisions from any agent, not only the conductor, answered to that agent's own lane.
3. **Published state** [[proposed]]: the feed built from each agent's own committed JSON (`status.json`), once an index of agents exists.
4. **Talking** [[proposed]]: a chat over the feed with Apple's model on the device, one question at a time through function calls; talking to a page by voice.
5. **The CI pipeline** [[proposed]]: each repository's latest run in the feed.

The work is tracked in [issue 054](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/054-owner-mode.md).
