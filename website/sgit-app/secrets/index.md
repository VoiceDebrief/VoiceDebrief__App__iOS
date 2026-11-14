# A secrets manager made of people and vaults

The design for the secrets manager in SGit Vaults, asked for by the owner on 14 November 2026. **This page is intention.** Built so far, compiled and tested but not yet used on a device: questions for the owner, the first secrets screens and the keys in iCloud Keychain (steps 1 to 3 below), described in the reality file. What is built is in [the reality file](../built/index.md), and this page will say plainly as each part arrives.

The owner's words: "a full-blown secrets manager ... passwords, secrets, passkeys", "the synchronisation between devices ... has to be completely transparent", "the collaboration of secrets between people", "how do we go from one person to two people, three, five, the whole group, where each one trusts the other", "a visual representation of the trust", "every team can do this independently", "it is also going to be the foundation for things like the CRM vault".

Earlier experiments it builds on: [secrets.sgit.ai](https://secrets.sgit.ai/) (a zero-knowledge secrets manager in the browser, designed, not built) and [pki.sgit.ai](https://pki.sgit.ai/) (people, their keys, and links that count only when both sides confirm them).

## The idea in one drawing

```
            you                         your team
   ┌──────────────────┐        ┌──────────────────────────┐
   │  iPhone  iPad  Mac│        │  Ana   Ben   Chloe  Dev  │
   │     \     |    /  │        │    \    |     |    /     │
   │   one key bundle  │◀──────▶│   cards swapped, both    │
   │   one inbox       │ trust  │   ways confirmed         │
   └────────┬─────────┘        └────────────┬─────────────┘
            │ opens                          │ opens
            ▼                                ▼
   ┌──────────────────┐        ┌──────────────────────────┐
   │  "My secrets"     │        │  "Team: devices"          │
   │   a vault         │        │   a vault, its key sealed │
   │   secrets/*.json  │        │   to each member          │
   └──────────────────┘        └──────────────────────────┘
            ▲                                ▲
            └──────── the same app, the same format ───────┘
                 a secret is a file in a vault; a team is
                 the people a vault's key was sealed to
```

Two things carry the whole design:

1. **A secret is a file in a vault.** One encrypted JSON file per entry, in the vault's `secrets/` folder. So everything vaults already do comes free: history of every change, signed by who made it; sync with no conflicts between different entries; the web Vault and the `sgit` command can read it; a vault on the device first and on a server when you choose.
2. **A team is the people a vault's key was sealed to.** No company account, no admin, no server of ours. Five people who have swapped cards can make a shared vault in one step, and anything in it is shared. A "CRM vault" later is the same thing with different files in it.

## What makes it different

Ordinary password managers keep your secrets in their company's cloud, behind an account they run, and sharing goes through their servers and their idea of a "team". This one has:

- **No account.** Nobody signs up for anything. A person is a key pair made on their own device.
- **No company in the middle.** The vault server stores ciphertext it cannot read; it never sees a name or a password.
- **Trust you can see.** A map of who has confirmed whom, built from both people's own word. Nobody can add themselves to your team.
- **History of every secret.** Who changed the Wi-Fi password, and when, signed by their device.
- **Secrets that can be given safely.** Sealed to one person's key; a photograph of the screen gives nothing away.
- **Agents are people too.** An AI session has a key and an inbox, and can be given exactly one secret, with a record that it was.
- **Nothing to export.** The format is open and the files are yours; the `sgit` command reads them on any computer.

### What the research says

[The field and the opportunity](opportunity/index.md) is a research brief on eleven managers and secret tools. Its points that change this design:

- **Every major manager's sharing trusts its own server to hand over the other person's public key.** A 2026 ETH Zurich study found more than 25 attacks on Bitwarden, LastPass and Dashlane by a dishonest server, sharing among them. Here the key comes from a card confirmed in person, never from the server. That is the strongest case for the in-person step, so the app should make it quick, not skip it.
- **Small-team sharing is where the others are weakest**: free plans stop at two people, and Apple's shared groups have no roles. A team of five with no admin and no account is the opening.
- **Agents leak secrets at scale** (about 28.65 million new secrets in public GitHub commits in 2025). Giving an agent one sealed secret, with a record, is a feature nobody has.
- **Removing someone** means a new vault key *and* changing what they saw. The app must say so, and offer a checklist.
- **Recovery** is where people give up and where security weakens. Proposed later: three of five people you trust each hold a sealed part.

Ten things this design could do better than all of them are ranked in the brief, each with its risk.

## From one person to a team

```
  1. alone          2. two people          3. three           5. the team
  ───────────       ──────────────         ──────────         ─────────────
     (you)           (you)═══(Ana)          (you)═══(Ana)       (you)══(Ana)
                                              ║     ╱            ║ ╲  ╱ ║
  a key bundle,     met in person:            ║   ╱             ║  ╳   ║
  made on this      scan each other's        (Ben)              ║ ╱  ╲ ║
  device; "My       cards, take a photo,                       (Ben)══(Chloe)
  secrets" vault    both confirm             Ana and Ben           ╲  ╱
  on this device                             confirm each           (Dev)
                    ═══ a link both          other too, or
                        people confirmed     only through you  a shared vault
                    ─── one side only                          for all five
```

**1. Alone.** The app makes a key bundle the first time it is needed, not at first launch. "My secrets" is a vault on this device. Nothing needs a network or an account.

**2. Two people, in person.** Each shows their card as a QR code; the other scans it. The app asks for a photo of the person in front of you (kept on your device) and what to call them. Each confirms. A link counts only when both have confirmed: one side alone is drawn dashed, as "waiting for Ana".

**2b. Two people, apart.** The card goes by WhatsApp, Signal or mail as a link. It is a weaker way of meeting, and the map says so ("met by message"), until you confirm the fingerprint on a call: four groups of four characters, read aloud.

**3 to 5. A group.** Each new person meets whoever is nearest. Ben, who has met only you, sees Ana as "known to someone you trust" and can meet her directly later. The map shows the links that exist; the app suggests the ones that are missing ("Ben and Chloe have not confirmed each other").

**The team's vault.** "Make a shared vault for these people": pick them on the map, name it ("Team: devices"), and the vault's key is sealed to each person's key and dropped in their inbox. Each of them sees it arrive and opens it with one tap. From then on, a password added by any of them is there for all of them, with who added it.

## The trust map

```
                       ┌───────┐
              ┌────────│  you  │────────┐
              │        └───┬───┘        │
           in person    in person    by message
              │            │         (dashed until
          ┌───┴───┐    ┌───┴───┐      confirmed)
          │  Ana  │════│  Ben  │    ┌ ─ ─ ─ ┐
          └───┬───┘    └───────┘      Chloe
              │                     └ ─ ─ ─ ┘
           in person
          ┌───┴───┐
          │  Dev  │   ◀ known to Ana, not yet to you
          └───────┘
```

Each person is drawn with their photo. A solid line is a link both people confirmed; dashed is one side only. A line says how they met. Tapping a person shows their fingerprint, when you met, the vaults you share and the secrets you gave each other. An agent is drawn as a robot face instead of a photo.

The map is computed on your device from what you know: your own contacts and the shared vaults' member lists. It is never published anywhere unless you choose to (pki.sgit.ai's register is optional, and off).

## A secret

```
  secrets/2026-11-14-office-wifi.json   (encrypted in the vault, as every file)
  ┌─────────────────────────────────────────────┐
  │ kind      wifi                               │
  │ name      Office Wi-Fi                        │
  │ fields    network: SGit-Office                │
  │           password: ••••••••••••             │
  │ note      the router is in the cupboard       │
  │ tags      office                              │
  │ changed   14 Nov 2026, by Ana (iPad)  ✓signed │
  └─────────────────────────────────────────────┘
```

Kinds, each with the fields it needs: **login** (site, username, password, one-time code), **device** (a laptop, tablet or phone and its passcode: the owner's first use), **Wi-Fi**, **card**, **note**, **token** (API keys), **vault key** and **read key** (opens the vault in one tap), **server access key**, **recovery code**. Values are shown only after Face ID, are copied to the clipboard for two minutes and never leave this device, and are hidden in the app switcher.

**Passkeys.** iOS lets a third-party app keep and use passwords and passkeys in other apps and in Safari only as an **AutoFill credential provider**, an extension that needs a capability switched on for the app in Apple's developer portal. Until then the app records which passkeys exist and where, without holding them. The owner's step is in the list at the end.

## Sync, without thinking about it

```
     iPhone                      iPad                       Mac
  ┌──────────┐               ┌──────────┐              ┌──────────┐
  │ vault    │◀── iCloud ───▶│ vault    │◀── iCloud ──▶│ vault    │
  │ keys     │   Keychain    │ keys     │   Keychain   │ keys     │
  └────┬─────┘               └────┬─────┘              └────┬─────┘
       │  push / pull             │                          │
       └──────────────▶  vault server (ciphertext)  ◀────────┘
```

Your vault keys live in iCloud Keychain, so every device signed into your Apple account opens the same vaults with no setup. The vaults themselves sync through the vault server: the app pulls when it opens and when it comes to the front, and pushes after every change. Two devices changing different secrets never conflict, because each secret is its own file; two changing the same secret at once keep both and ask which is right.

Writing to the server needs an access key; the owner will connect payment for that. Until a person has one, "My secrets" stays on the device it was made on, and the app says so.

## Messages and questions

People talk through their inboxes: a sealed note, a card, a secret, a vault invitation. The same channel is how the app can ask **its owner** questions while it is being built: a Questions screen where a question waits, and the answer can be typed or spoken with the keyboard's dictation, and goes to the developers sealed to their key.

## What is built in which order

| Step | What | Depends on |
|---|---|---|
| 1 | Questions for the owner, answered by typing or dictation | nothing new |
| 2 | Secrets: entries in a vault's `secrets/` folder, the kinds above, Face ID, copy, history | nothing new |
| 3 | Vault keys in iCloud Keychain, pull on open, push on change | an access key for the server part |
| 4 | People: card, scan, photo, two-way confirmation (the people session's screens) | SGitPeople |
| 5 | The trust map | step 4 |
| 6 | A shared vault for chosen people, sealed to each | step 4 and an inbox each |
| 7 | AutoFill: passwords and passkeys in Safari and other apps | the owner switches on the capability |

## For the owner

Questions are also in the app (Settings, Questions) once step 1 is built.

1. **Where "My secrets" lives.** Proposed: a vault like any other (on the device first, on the server once there is an access key). The alternative is iCloud Keychain only, which syncs for free but cannot be shared or read by the `sgit` command.
2. **Photos of people.** Proposed: kept on your device only; not in the card, so a card stays small enough for one QR code.
3. **AutoFill and passkeys.** Needs "AutoFill Credential Provider" switched on for `ai.sgit.vaults.app` in the Apple developer portal, and an App Group. Shall I prepare it?
4. **Recovery.** If all your devices are lost, the vault keys go with iCloud Keychain. Proposed for later: a printed recovery sheet, or a second person who holds a sealed copy.
5. **What a member of a shared vault can do.** Today, everything (they hold the vault key). Read-only members are possible with a read key; "may add, may not delete" needs the server.

## Ideas

- **A team with no admin and no account** [[proposed]]: five people swap cards and confirm each other, then share a vault, with no sign-up, invoice or IT person.
- **Sharing a server cannot redirect** [[proposed]]: the key a secret is sealed to comes from a card confirmed in person, never from the server, which shuts out the key-swapping attacks found in other managers in 2026.
- **One secret for one agent** [[proposed]]: give an AI session exactly one API key, sealed to its key, with a record of when and to whom.
- **Signed history of every secret** [[proposed]]: who changed the router password and when, signed by their device, with the earlier version one tap away.
- **Ask someone outside the team for a secret** [[proposed]]: a contractor drops the Wi-Fi or a server key into your inbox; they get no way to read anything back.
- **Rotation on a branch** [[proposed]]: change a key, test it, then merge, so the team is never half on the old one and half on the new.
- **Recovery through people you trust** [[proposed]]: lose every device and get back in with three of five people each holding a sealed part; no company reset.
- **Leaving someone out, honestly** [[proposed]]: removing a member makes a new vault key and shows the checklist of secrets they saw, with a change action for each.
- **A spotted secret** [[proposed]]: Apple's on-device model notices a key pasted into a note or a file and offers to move it into a secret.
- **A history that does not show the secret** [[proposed]]: someone with a read key on the history sees who changed which entry and when, and which fields, without ever seeing a value.
- **Where each secret came from** [[proposed]]: every entry says who gave it to you and through which confirmed card, so a secret of unknown origin stands out.
- **Proof you can check without the app** [[proposed]]: the open `sgit` command on any computer clones the vault and checks every signature; nothing rests on trusting this app or its maker.
- **A lost phone, in one screen** [[proposed]]: which secrets that device held, one action to stop trusting its key, and the checklist of what to change.
- **Break glass, with time to say no** [[proposed]]: a trusted person asks for a sealed secret through your inbox; it opens for them only if you have not refused within a set number of hours.
- **A machine that hands in new keys** [[proposed]]: a server or CI job changes its own credential and drops the new one into your inbox; it can write there, never read the vault.
- **Works on a plane** [[proposed]]: every secret is in a vault on the device; reading, adding and changing need no network, and sync happens when there is one.
- **A share with an end date** [[proposed]]: one entry sealed to one card, with a date after which the app reminds you to change it, because a copy given cannot be taken back.
- **The trust map** [[proposed]]: a drawing of the people you have met, with their photos, solid where both confirmed and dashed where one side only.
- **The same vaults on every device** [[unverified]]: vault keys in iCloud Keychain, one item each, so an iPhone, iPad and Mac open the same vaults with nothing to set up.
- **Secrets as files in vaults** [[unverified]]: each entry one encrypted JSON file, behind Face ID, with a strong-password maker.
- **Questions for the owner, by voice** [[unverified]]: the people building the app ask, and the owner answers by choosing, typing or speaking.
