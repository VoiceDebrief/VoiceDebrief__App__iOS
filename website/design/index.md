# The design: a recorder that does not lose things

What the app should look like and how it should behave, agreed over two rounds between a product agent and a design agent on 13 November 2026, with the engineer reconciling. This page is intention, like the [plan](../plan/index.md); [what is built](../built/index.md) says how much of it exists.

## The product, in one sentence

A voice recorder that turns each recording into a transcript and a short debrief on the device, keeps everything on the device, and copies it, encrypted, to vaults you own and to lanes you choose.

Three jobs, in this order:

1. **Capture without loss.** A recording is on disk as it is spoken and belongs to a note before the first word. A crash, a call, a model that fails or closing the app cannot lose it.
2. **Give back something readable and findable.** A transcript always; a debrief when the model can; a library to find it again.
3. **Move it where it is needed.** Save to a vault, send to a lane, share as text.

## Decisions

| | Decision |
|---|---|
| Tabs | Four: Record, Library, Vaults, Settings. A tab bar on iPhone, a sidebar on iPad and Mac |
| No setup | Nothing is needed to record and keep notes on the device: no vault, no account, no token |
| Keeping | Saving to the device is automatic and has no switch. Saving to a vault is by choice |
| Sending | Sending to a lane is never automatic. It asks every time and names the key the note is encrypted to |
| At Stop | The note opens at once and fills in: the transcript first, then the debrief |
| Reading order | "In one sentence" first, then key points, then actions. Stored order is unchanged. If the model lost the headings, its text is shown as one plain block |
| Actions | Share, Save to vault and Send are visible, each showing its own state. Nothing core is hidden in a menu |
| Words | Vault, lane, debrief, access token: the owner's words. A library item is a "note", because a note may have no debrief |
| Honesty | The privacy line says where this note actually is. No step is shown as done before it is. No player is shown before there is one |
| Vault key | The vault screen says plainly that the key lives on this device only and that losing it loses the vault |
| Deleting | Deleting a note removes it from this device. A copy in a vault stays, and the confirmation says so |

## The screens

**Record.** One red control, 88 points across, pinned at the bottom where a thumb reaches; it does not move between idle and recording. Above it while recording: a large timer, the microphone's level as bars, and the words as they are spoken. Idle: the three most recent notes. The language is a small menu in the toolbar.

**Note.** Date and details; one line saying where the note is; the audio player; the debrief as cards; the transcript, each line a button that moves the audio to that moment; then Share, Save to vault and Send.

**Library.** Notes by day, newest first. A row is the note's one sentence, the time and length, and at most one mark: working, something wrong, or saved to a vault.

**Vaults.** Opens with what a vault is in three lines and one button. Each vault shows what was saved first; files, history, branches and the key sit behind "Technical".

**Settings.** Language, saving, lanes, and an Advanced area for diagnostics and the vault engine's log.

**Look.** VoiceDebrief's green as the accent, red only for recording and failures, amber for anything degraded. System type. Cards with a hairline, no shadows. Content is held to a readable width so that a wide Mac window is not a stretched phone. The colours, type, icons and pictures are set out in [the visual identity](identity/index.md).

## Three builds

Each is small enough to test on a device from a screenshot before the next starts.

| Build | What |
|---|---|
| A | Capture without loss and the new shell: the note created when recording starts, the recording in a form that survives a crash, the library, four tabs, the record screen |
| B | The note and the library proper: cards, the audio player, tap a line to hear it, honest banners, the colours and widths |
| C | Keeping and sending: several vaults and several lanes with names, saved and sent states on each note, "also save to vault", retry |

## Open questions for the owner

1. Should saving to a vault be automatic once a vault is chosen? Recommended: yes, behind one switch, off until a vault exists. **Answered by the owner, 13 November 2026: yes. Finishing a note saves it to the vault unless it is cancelled; the finishing control is green, and discarding is red, out of the way and takes two presses** (issue 022).
2. May a note ever be sent to a lane automatically? Recommended: not yet; later, per lane, only for lanes the owner added. **The owner, same day: sending is a main activity, not a fringe one. Lanes are recipients with names, a finished note offers them as buttons, and sending may be automatic per recipient** (issue 019).
3. Does deleting a note in the app delete it from a vault? Recommended: no.
