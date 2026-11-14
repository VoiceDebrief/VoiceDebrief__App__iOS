# Ideas and where they stand

Every idea and request for the two apps, from the [issues](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/tree/dev/issues), the [articles](../articles/index.md) and the reality files ([VoiceDebrief](../built/index.md), [SGit Vaults](../sgit-app/built/index.md)), with its status. This page and the Ideas screen in the app are generated from those files by `website/admin/ideas.mjs`; nothing here is written by hand. The rules that decide a status are at the top of that script, and every idea in the app shows the sentence that decided its own. The machine-readable form is [ideas.json](ideas.json).

| Status | Meaning | How many |
|---|---|---|
| Seen working | Built, and a run proved it: CI, a device or a server. | 27 |
| Built, untried | In the app or the repository, but not yet proven by a run on a device. | 65 |
| In progress | Begun: part of it is built or a release has touched it. | 33 |
| Proposed | Asked for or described; nothing of it is built. | 38 |
| Parked | Waiting: on the owner, on Apple, or scheduled for later. | 6 |

## Seen working

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
| Prove vault writes against the live server | Issue | VoiceDebrief |   |   | [004](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/004-live-vault-writes.md) |
| PKIKit, the key bundle | Issue | VoiceDebrief | Settings: Identity | [v0.1.29](../versions/v0.1.29/index.md) | [005](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/005-pkikit.md) |
| TestFlight for the sgit app | Issue | SGit Vaults | SGit Vaults |   | [101](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/101-sgit-app-testflight.md) |
| The app skeleton | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| Send a note to the developer | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Create a vault | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Save a debrief to a vault | Feature | VoiceDebrief | Vaults tab |   | [reality file](../built/index.md) |
| The people layer in Python, people.py | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| A conductor's inbox | Feature | VoiceDebrief | The repository: tools/conductor |   | [reality file](../built/index.md) |
| The key bundle, PKIKit | Feature | VoiceDebrief | Settings: Identity |   | [reality file](../built/index.md) |
| The About screen | Feature | VoiceDebrief | Settings: What this build does |   | [reality file](../built/index.md) |
| The vault engine | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| A door on any site | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| The build pipeline | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| Pictures of every screen | Feature | VoiceDebrief | The repository: pictures of every screen; The repository: CI |   | [reality file](../built/index.md) |
| Reviews from the pictures | Feature | VoiceDebrief | Record tab: the briefing card; The repository: pictures of every screen | [v0.1.29](../versions/v0.1.29/index.md) [v0.1.40](../versions/v0.1.40/index.md) | [reality file](../built/index.md) |
| Sample data for the pictures | Feature | VoiceDebrief | The balance in the top bar; Settings: Recipients |   | [reality file](../built/index.md) |
| TestFlight upload | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Vault interop | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| PKI interop | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| The site | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Files over 4 MB in the vault engine | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| The app builds and its tests pass | Feature | SGit Vaults | SGit Vaults |   | [reality file](../sgit-app/built/index.md) |
| Adding files, underneath the screens | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| TestFlight upload | Feature | SGit Vaults | SGit Vaults: Gallery; SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| A vault made on this device | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| A picture of every screen | Feature | SGit Vaults | SGit Vaults: Gallery; SGit Vaults: a vault; SGit Vaults: Share |   | [reality file](../sgit-app/built/index.md) |

## Built, untried

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
| Say what Send does, on the note | Issue | VoiceDebrief | A note: the send bar; Library, then a note; Settings: Recipients |   | [031](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/031-say-what-send-does.md) |
| States that say what to do next | Issue | VoiceDebrief | Library, then a note; Library tab; Record tab | [v0.1.29](../versions/v0.1.29/index.md) | [036](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/036-states-that-say-what-to-do.md) |
| A copy off the phone that anyone can make | Issue | VoiceDebrief | Library, then a note | [v0.1.29](../versions/v0.1.29/index.md) | [039](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/039-a-copy-off-the-phone.md) |
| A way to say no in each confirmation | Issue | VoiceDebrief | A note: the send bar; Library, then a note; Record tab | [v0.1.29](../versions/v0.1.29/index.md) | [040](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/040-a-way-to-say-no.md) |
| A send that can be seen, stopped and not lost | Issue | VoiceDebrief | A note: the send bar; Library, then a note; Library tab | [v0.1.40](../versions/v0.1.40/index.md) | [043](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/043-a-send-that-can-be-seen-stopped-and-not-lost.md) |
| Two symbols with no words at the top of the first screen | Issue | VoiceDebrief | Library tab; Record tab; The balance in the top bar | [v0.1.40](../versions/v0.1.40/index.md) | [044](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/044-two-symbols-with-no-words.md) |
| Vaults are local first; a server is a remote | Issue | VoiceDebrief | Vaults tab |   | [011](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/011-local-vaults-and-remotes.md) |
| Vault keys and server tokens in iCloud Keychain, on by default | Issue | VoiceDebrief | Vaults tab; Settings: Identity | [v0.1.33](../versions/v0.1.33/index.md) | [017](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/017-key-sync.md) |
| Play a recording, and show how long an interrupted one is | Issue | VoiceDebrief | A note: the player; Library, then a note |   | [029](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/029-play-a-recording.md) |
| Record again while the last note is being written up | Issue | VoiceDebrief | Record tab | [v0.1.29](../versions/v0.1.29/index.md) | [030](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/030-record-while-the-last-note-is-written-up.md) |
| The gist first on a note | Issue | VoiceDebrief | A note: Clean text; A note: the send bar; Library, then a note |   | [034](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/done/034-the-gist-first-on-a-note.md) |
| Capture without loss | Feature | VoiceDebrief | Library tab |   | [reality file](../built/index.md) |
| Library on the device | Feature | VoiceDebrief | Library, then a note; Library tab |   | [reality file](../built/index.md) |
| The shell | Feature | VoiceDebrief | Record tab; Settings: Diagnostics; Settings tab |   | [reality file](../built/index.md) |
| Record or open a voice note | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Transcript on the device | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Debrief on the device | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Live text and a level display while recording | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| Vaults on the device | Feature | VoiceDebrief | Vaults tab; The repository: CI |   | [reality file](../built/index.md) |
| Servers as remotes | Feature | VoiceDebrief | Vaults tab |   | [reality file](../built/index.md) |
| Push and pull | Feature | VoiceDebrief | Vaults tab |   | [reality file](../built/index.md) |
| Vaults from earlier builds | Feature | VoiceDebrief | Vaults tab |   | [reality file](../built/index.md) |
| Vault keys and server tokens in iCloud Keychain | Feature | VoiceDebrief | Vaults tab; The repository: CI |   | [reality file](../built/index.md) |
| Record while a note is written up | Feature | VoiceDebrief | Record tab |   | [reality file](../built/index.md) |
| Play a recording | Feature | VoiceDebrief | A note: the player |   | [reality file](../built/index.md) |
| A briefing on opening | Feature | VoiceDebrief | Record tab; Record tab: the briefing card |   | [reality file](../built/index.md) |
| The Guide: ideas, what is new, feature guides | Feature | VoiceDebrief | Library tab; Record tab: the briefing card |   | [reality file](../built/index.md) |
| A welcome on the first launch | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Where the work happens | Feature | VoiceDebrief | Record tab; Settings: Identity; Settings: Recipients |   | [reality file](../built/index.md) |
| Finish by voice or by a button off the screen | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Talk to Claude | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Agents | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Every section in plain sight | Feature | VoiceDebrief | Record tab |   | [reality file](../built/index.md) |
| Your activity | Feature | VoiceDebrief | The repository: tools/conductor |   | [reality file](../built/index.md) |
| A note's journey after Finish | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Record a note for someone | Feature | VoiceDebrief | Record tab; Settings: Recipients |   | [reality file](../built/index.md) |
| A send that is not lost | Feature | VoiceDebrief | Record tab; Record tab: the briefing card; Settings: Recipients |   | [reality file](../built/index.md) |
| Finish and send in one press | Feature | VoiceDebrief | Record tab; Settings: Recipients |   | [reality file](../built/index.md) |
| Send without waiting | Feature | VoiceDebrief | A note: the send bar; Library, then a note; Settings: Recipients |   | [reality file](../built/index.md) |
| The Lab, experiment L01: one prompt, tools on and off | Feature | VoiceDebrief | Settings: Experiments, the Lab; The repository: CI |   | [reality file](../built/index.md) |
| The model door, first slice | Feature | VoiceDebrief | Settings: Experiments, the Lab |   | [reality file](../built/index.md) |
| Recipients, added by QR code | Feature | VoiceDebrief | Settings: Recipients |   | [reality file](../built/index.md) |
| A clean text, with questions | Feature | VoiceDebrief | A note: Clean text; Library, then a note |   | [reality file](../built/index.md) |
| Credit that counts down, with a simulated top-up | Feature | VoiceDebrief | The balance in the top bar; Settings: Recipients |   | [reality file](../built/index.md) |
| A finished note saves itself to a vault | Feature | VoiceDebrief | Record tab; Settings: Save to a vault; Settings tab |   | [reality file](../built/index.md) |
| The people layer, SGitPeople | Feature | VoiceDebrief | Settings: Recipients | [v0.1.54](../versions/v0.1.54/index.md) | [reality file](../built/index.md) |
| The user's key pair | Feature | VoiceDebrief | Settings: Identity |   | [reality file](../built/index.md) |
| The device's key pair | Feature | VoiceDebrief | Vaults tab; Settings: Identity |   | [reality file](../built/index.md) |
| Vouching for a device | Feature | VoiceDebrief | Settings: Identity |   | [reality file](../built/index.md) |
| A person in the register, optionally | Feature | VoiceDebrief | Settings: Identity |   | [reality file](../built/index.md) |
| Diagnostics | Feature | VoiceDebrief | Settings: Diagnostics |   | [reality file](../built/index.md) |
| The visual identity | Feature | VoiceDebrief | Record tab; Settings: Identity; The repository: CI |   | [reality file](../built/index.md) |
| Recording with the screen locked or the app in the background: the audio background mode is declared | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| The access key on the Create screen | Feature | SGit Vaults | SGit Vaults: the Create sheet |   | [reality file](../sgit-app/built/index.md) |
| Drag and drop | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| A folder tree on a wide screen | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| A gallery of vaults | Feature | SGit Vaults | SGit Vaults: Gallery |   | [reality file](../sgit-app/built/index.md) |
| Vaults on the device | Feature | SGit Vaults | SGit Vaults |   | [reality file](../sgit-app/built/index.md) |
| Adding photos, videos and files, the screens | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| Browsing | Feature | SGit Vaults | SGit Vaults: a vault; SGit Vaults: Share |   | [reality file](../sgit-app/built/index.md) |
| Saving a folder out | Feature | SGit Vaults | SGit Vaults: a vault; SGit Vaults: Share |   | [reality file](../sgit-app/built/index.md) |
| The web Vault inside the app | Feature | SGit Vaults | SGit Vaults: a vault |   | [reality file](../sgit-app/built/index.md) |
| Your activity | Feature | SGit Vaults | SGit Vaults: Share; SGit Vaults: Settings |   | [reality file](../sgit-app/built/index.md) |
| Sharing a vault | Feature | SGit Vaults | SGit Vaults: Share |   | [reality file](../sgit-app/built/index.md) |
| History | Feature | SGit Vaults | SGit Vaults: History |   | [reality file](../sgit-app/built/index.md) |

## In progress

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
| Signing and TestFlight | Issue | VoiceDebrief |   |   | [001](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/001-signing-and-testflight.md) |
| What SGitVault still lacks | Issue | VoiceDebrief |   |   | [006](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/006-vault-engine-gaps.md) |
| Credit, charging per use, top-up | Issue | VoiceDebrief | The balance in the top bar; Settings: Recipients | v0.1.20 | [008](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/008-credits.md) |
| The lab, first experiment (L01): one prompt, tools on and off | Issue | VoiceDebrief | Settings: Experiments, the Lab; The repository: CI |   | [012](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/012-lab-one-prompt.md) |
| Pictures of every screen, and synthetic users | Issue | VoiceDebrief | Settings: Experiments, the Lab; The repository: pictures of every screen | [v0.1.29](../versions/v0.1.29/index.md) | [016](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/016-screens-and-synthetic-users.md) |
| The user's key pair, the device key, and vouching (with issue 005) | Issue | VoiceDebrief | Vaults tab; Settings: Identity; The repository: CI | [v0.1.29](../versions/v0.1.29/index.md) | [018](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/018-identity.md) |
| Lanes are recipients, and the app has an inbox | Issue | VoiceDebrief | Library, then a note; Settings: Recipients; The repository: tools/conductor |   | [019](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/019-recipients-and-inbox.md) |
| Finishing saves to the vault; discarding is the awkward path | Issue | VoiceDebrief |   | v0.1.13 | [022](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/022-finish-saves-to-the-vault.md) |
| Files over 4 MB in a vault (presigned upload and download) | Issue | VoiceDebrief | Vaults tab | v0.1.19 | [023](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/023-large-files-in-a-vault.md) |
| A clean text instead of a summary, with questions where the note is unclear | Issue | VoiceDebrief | A note: Clean text |   | [024](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/024-clean-text-and-clarifications.md) |
| The version in plain sight, release notes worth reading, and a briefing on opening | Issue | VoiceDebrief | Library tab; Record tab: the briefing card; The version badge in the top bar | [v0.1.35](../versions/v0.1.35/index.md) | [025](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/025-version-and-release-notes-in-the-app.md) |
| Act on a note at once: send without waiting, controls that do not move | Issue | VoiceDebrief | Library, then a note; Record tab; Settings: Recipients | [v0.1.30](../versions/v0.1.30/index.md) | [026](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/026-act-on-a-note-at-once.md) |
| Show where the work happens; small remarks from the model; talking to the app | Issue | VoiceDebrief | Record tab | [v0.1.31](../versions/v0.1.31/index.md) | [027](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/027-show-where-work-happens-and-talk-to-the-app.md) |
| The device key signs every commit, and the vault says whose device it is | Issue | VoiceDebrief | Vaults tab; Settings: Identity |   | [028](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/028-device-key-signs-commits.md) |
| Explain the balance where it is shown | Issue | VoiceDebrief | Record tab; The balance in the top bar | [v0.1.29](../versions/v0.1.29/index.md) | [032](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/032-explain-the-balance.md) |
| The log cannot tell a server from the device | Issue | VoiceDebrief | Settings: Recipients; Settings: Every step the vault engine took |   | [033](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/033-the-log-cannot-tell-a-server-from-the-device.md) |
| A readable width on iPad | Issue | VoiceDebrief | Library, then a note; Library tab; Record tab |   | [035](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/035-a-readable-width-on-ipad.md) |
| A vault, for someone who has never met one | Issue | VoiceDebrief | Vaults tab |   | [037](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/037-a-vault-for-someone-who-has-never-met-one.md) |
| What the pictures could not show | Issue | VoiceDebrief | Library, then a note; Library tab; Record tab |   | [038](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/038-what-the-pictures-could-not-show.md) |
| Diagnostics describes a pasted lane that nothing uses | Issue | VoiceDebrief | A note: the send bar; Settings: Recipients; Settings: Diagnostics | [v0.1.29](../versions/v0.1.29/index.md) | [041](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/041-diagnostics-describes-a-lane-nothing-uses.md) |
| Two sentences that say the wrong thing | Issue | VoiceDebrief | Vaults tab; Settings tab | [v0.1.40](../versions/v0.1.40/index.md) | [045](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/045-two-sentences-that-say-the-wrong-thing.md) |
| The sgit app, milestone one | Issue | SGit Vaults | SGit Vaults: Share |   | [100](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/100-sgit-app-milestone-one.md) |
| The sgit app after milestone one | Issue | SGit Vaults | SGit Vaults: Share |   | [103](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/103-sgit-app-after-milestone-one.md) |
| A gallery of vaults, opened in a browser inside the app | Issue | SGit Vaults | SGit Vaults: Gallery |   | [107](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/107-sgit-app-gallery.md) |
| sgit app: a teammate sent a vault key cannot add to it | Issue | SGit Vaults | SGit Vaults: Share; SGit Vaults: Settings | [v0.1.45](../versions/v0.1.45/index.md) | [110](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/110-sgit-app-a-teammate-cannot-add-without-an-access-key.md) |
| sgit app: say whether a file has arrived | Issue | SGit Vaults | SGit Vaults: a vault | [v0.1.44](../versions/v0.1.44/index.md) | [111](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/111-sgit-app-has-it-arrived.md) |
| sgit app: who added it | Issue | SGit Vaults | SGit Vaults: History | [v0.1.44](../versions/v0.1.44/index.md) | [112](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/112-sgit-app-who-added-it.md) |
| sgit app: sharing, for someone who was never told what a key is | Issue | SGit Vaults | SGit Vaults: the Create sheet; SGit Vaults: Share; SGit Vaults: Settings | [v0.1.44](../versions/v0.1.44/index.md) | [113](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/113-sgit-app-sharing-for-someone-who-was-not-told-what-a-key-is.md) |
| sgit app: getting a folder out, at full quality | Issue | SGit Vaults | SGit Vaults: a vault; SGit Vaults: Share | [v0.1.44](../versions/v0.1.44/index.md) | [114](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/114-sgit-app-getting-files-out.md) |
| sgit app: the Create sheet, the four keys, and smaller things | Issue | SGit Vaults | SGit Vaults: the Create sheet; SGit Vaults: a vault; SGit Vaults: History | [v0.1.44](../versions/v0.1.44/index.md) | [115](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/115-sgit-app-the-create-sheet-and-the-words.md) |
| sgit app: what the pictures could not show | Issue | SGit Vaults | SGit Vaults: the Create sheet; SGit Vaults: a vault; SGit Vaults: Share | [v0.1.44](../versions/v0.1.44/index.md) | [116](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/116-sgit-app-what-the-pictures-could-not-show.md) |
| People, messages and secrets (the SGitPeople package) | Issue | SGit Vaults | SGit Vaults | [v0.1.54](../versions/v0.1.54/index.md) | [200](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/200-people-messages-and-secrets.md) |
| People, messages and secrets: the layer under both apps | Article | Both |   |   | [article](../articles/people-messages-and-secrets/index.md) |

## Proposed

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
| The four spikes | Issue | VoiceDebrief | Settings: Diagnostics |   | [002](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/002-spikes.md) |
| Read WhatsApp's Ogg Opus (spike S4) | Issue | VoiceDebrief |   |   | [009](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/009-ogg-opus.md) |
| Doors: a harness inside the app | Issue | VoiceDebrief | Settings: Experiments, the Lab |   | [013](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/013-harness-doors.md) |
| Several vaults and several lanes, by name (build C of the design) | Issue | VoiceDebrief |   |   | [014](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/014-vaults-and-lanes-register.md) |
| Show the flow as it happens | Issue | VoiceDebrief |   |   | [020](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/020-show-the-flow.md) |
| Analyse while recording: a semantic graph, a title, pictures | Issue | VoiceDebrief |   |   | [021](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/021-analysis-while-recording.md) |
| Prove the app's large-file exchange against the live server | Issue | SGit Vaults | SGit Vaults: a vault |   | [102](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/102-sgit-app-live-server.md) |
| "Send to vault" from Photos and Files (a share extension) | Issue | SGit Vaults | SGit Vaults: a vault; SGit Vaults: Share |   | [105](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/105-sgit-app-share-extension.md) |
| A viewer for chat-archive results, as a separate app | Issue | SGit Vaults | SGit Vaults: Gallery |   | [106](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/106-chat-archive-viewer.md) |
| sgit app: a record of every action, on every device | Issue | SGit Vaults | SGit Vaults: Share; SGit Vaults: Settings |   | [117](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/117-sgit-app-observability-across-devices.md) |
| sgit app: the web Vault inside the app, and its features natively | Issue | SGit Vaults | SGit Vaults: a vault; SGit Vaults: Settings |   | [118](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/118-sgit-app-the-web-vault-inside-the-app.md) |
| A harness inside the app | Article | Both |   |   | [article](../articles/a-harness-inside-the-app/index.md) |
| A private voice note, and what it would take to use it in a clinic | Article | Both |   |   | [article](../articles/a-private-voice-note-and-a-clinic/index.md) |
| Synthetic users | Article | Both |   |   | [article](../articles/synthetic-users/index.md) |
| The lab | Article | Both |   |   | [article](../articles/the-lab/index.md) |
| The vault is a version-controlled store | Article | Both |   |   | [article](../articles/the-vault-is-a-version-controlled-store/index.md) |
| Two decision engines | Article | Both |   |   | [article](../articles/two-decision-engines/index.md) |
| Voice everywhere | Article | Both |   |   | [article](../articles/voice-everywhere/index.md) |
| Where each key lives | Article | Both |   |   | [article](../articles/where-each-key-lives/index.md) |
| Receiving a voice note from the share sheet (WhatsApp) | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Decoding WhatsApp's Ogg Opus | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Saved and sent states on a note; saving to a vault automatically; an inbox in the app; the app's own QR code, so a conductor can write back | Feature | VoiceDebrief | Library, then a note |   | [reality file](../built/index.md) |
| Apple's larger model on Private Cloud Compute, as an option | Feature | VoiceDebrief | The repository: CI |   | [reality file](../built/index.md) |
| Translation, classification, citations of time in the debrief | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| The passkey ceremony, the account, the recovery code | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Creating an account, adding a door, merge, audio over 3.8 MB in a vault | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Debriefs signed by the device key; the vouching row in a vault's own screen | Feature | VoiceDebrief | Vaults tab |   | [reality file](../built/index.md) |
| The answer from pki.sgit.ai handed to the app by iOS | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Checking that an issuer chains to the register's root through its links; withdrawing a vouching statement; the user's key in a master vault behind a passkey; exporting the identity to sgit's key store from the app | Feature | VoiceDebrief | Settings: Identity |   | [reality file](../built/index.md) |
| A merge when a device and its server have both changed; pushing or pulling a branch other than current; several servers for one vault; pushing automatically | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| The share extension, App Intents | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Paying for credit through the App Store; the ledger in the user's vault; anything that stops someone editing their own balance | Feature | VoiceDebrief | The balance in the top bar |   | [reality file](../built/index.md) |
| The App Store | Feature | VoiceDebrief |   |   | [reality file](../built/index.md) |
| Local-first vaults and named remotes; keys in iCloud Keychain | Feature | SGit Vaults | SGit Vaults | [v0.1.33](../versions/v0.1.33/index.md) | [reality file](../sgit-app/built/index.md) |
| A share extension; background uploads | Feature | SGit Vaults | SGit Vaults: Share |   | [reality file](../sgit-app/built/index.md) |
| A merge for colliding edits; branches | Feature | SGit Vaults | SGit Vaults |   | [reality file](../sgit-app/built/index.md) |
| A read-only token that can be revoked | Feature | SGit Vaults | SGit Vaults |   | [reality file](../sgit-app/built/index.md) |
| Video thumbnails; streaming a video without fetching it whole | Feature | SGit Vaults | SGit Vaults |   | [reality file](../sgit-app/built/index.md) |

## Parked

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
| The passkey's relying party (decision D1) | Issue | VoiceDebrief | Settings: Identity |   | [003](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/003-passkey-relying-party.md) |
| Stop SGitVault being two copies (decision D8) | Issue | VoiceDebrief |   |   | [007](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/007-shared-vault-package.md) |
| Judge Apple's models on real voice notes (spike S2) | Issue | VoiceDebrief | Settings: Diagnostics |   | [010](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/010-judge-the-models.md) |
| The larger Apple model on Private Cloud Compute, as an option | Issue | VoiceDebrief | Settings: Experiments, the Lab; The repository: CI |   | [015](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/015-private-cloud-compute.md) |
| Telling speakers apart | Issue | VoiceDebrief | Settings: Identity; Settings: Experiments, the Lab |   | [042](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/042-speaker-separation.md) |
| A read-only share that can be taken back | Issue | SGit Vaults | SGit Vaults: Share |   | [104](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/104-revocable-read-only-share.md) |
