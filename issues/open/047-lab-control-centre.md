# 047: The lab, second experiment (L02): the control centre

**Status:** open. From three voice notes the owner recorded while driving, 14 November 2026, relayed by the
parent session. See the articles "The lab" and "Two decision engines".

Giving instructions is a different mode from thinking aloud. In a control mode the screen shows the actions
and the reactions, not the transcript: an instruction is heard, an action is proposed, and the person says
do it, not this, or edits it. No black magic: choose, see the pipeline, then trigger it. The phrases that
trigger an action are listed and can be changed.

## Where it stands (14 November 2026)

Built and in the Lab: sentences in (spoken, typed, or fourteen test sentences); two engines, the fixed
phrases and the on-device model with one tool for each of seven actions; a card for each proposal with its
state and Do it, Not this, Edit; actions that may go ahead without asking; the phrase list, editable and
kept on the device; a tally and a JSON log. Compiled and unit tested; never run against a model.

## What it does not do yet

- **It carries out two actions only**, the two that are safe to undo: opening a section (through
  `LabActionHost.openSection`, a closure the session that owns `RootView` sets) and finding a note (a
  read-only search, listed on the card; it does not open the note). Finish the recording, send, save, record
  for a time and cancel are recorded only: they touch `DebriefSession` and the send path, which other sessions own.
- Opening a section leaves the Lab screen, which stops the listening: a control mode that stays up while
  the app moves beneath it needs a place of its own in the shell.
- The model is asked about every settled piece of speech, with no pause rule of its own and no state handed
  to it (whether a recording is running, who the recipients are).
- Portuguese: the phrases and the test sentences are English only.

## What decides the next step

The owner runs the test sentences on an iPhone, an iPad and a Mac and sends back the log. If the model
proposes the right action often enough and fast enough, wire the actions that are safe to undo first. If it
does not, the phrases are the engine and the model is not asked.

## Third action: record a note for someone (14 November 2026)

`recordTo`, through `LabActionHost.startRecording`, set by the session that owns recording. Agreed with the
parent session: it is not safe to undo, because a note recorded for a person is sent when it is finished and
a spoken finish needs no tap. So it always waits for Do it, has no switch under "Without asking", and the
card names what the app resolved. The app's side matches the name exactly, ignoring case, and refuses
anything else with the names that exist. The Lab stops its own listening before the recording starts.

## Listening and a recording's microphone (14 November 2026)

Three notes from build 0.1.72 arrived as digital silence. Reading L02's Listen for a cause found two ways it
could have done it: it switched the shared audio session off when it stopped, after an await, which could
land on a recording that had begun in the meantime or was running when Listen was pressed; and a Listen
waiting on the microphone permission could start after the screen was left. Both are closed: the Lab never
switches the session off, refuses to listen while `LabActionHost.isRecording` says a note is being recorded,
abandons a start overtaken by a stop, and stops when the app goes to the background. **Not proven to be the
cause**: nobody has reproduced the silence, and the same pattern (an audio session switched off after an
await) should be looked for wherever else the app stops listening or playing.

## After the owner's first try (14 November 2026, 18:11)

"The control centre is really cool." Asked for: everything being heard shown while it listens, and the flow
from words to proposal to action made easier to follow. Done: a strip of the live words at the top, and a
numbered card for every sentence that says what each engine made of it. That is the first word from a
device about L02; no log has come back yet, so how often the model was right is still not known.
