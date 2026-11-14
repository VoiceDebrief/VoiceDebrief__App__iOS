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

- **It carries no action out.** Do it records the choice. Wiring an action to the app (finish the recording,
  send, save, open a section) touches `DebriefSession`, `RootView` and the send path, which other sessions own.
- The model is asked about every settled piece of speech, with no pause rule of its own and no state handed
  to it (whether a recording is running, who the recipients are).
- Portuguese: the phrases and the test sentences are English only.

## What decides the next step

The owner runs the test sentences on an iPhone, an iPad and a Mac and sends back the log. If the model
proposes the right action often enough and fast enough, wire the actions that are safe to undo first. If it
does not, the phrases are the engine and the model is not asked.
