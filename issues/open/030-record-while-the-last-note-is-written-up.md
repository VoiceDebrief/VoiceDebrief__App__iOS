# 030: Record again while the last note is being written up

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the main session (`RecordView`, `DebriefSession`).

Finding 2. Screen `record.working`. Found by the driver (it blocked the task: a second memo straight after the
first) and by the user who lost a recording.

While a note is being transcribed and debriefed the record control is grey and says "Finishing the last note",
with no word on how long. A thought that arrives then is lost, which is against the standing position "never
lose a recording".

To do: let a recording start whatever the pipeline is doing. The session takes one note through the pipeline at
a time, so this needs a queue of notes waiting to be processed, or a recording that waits its turn. If it cannot
be done at once, say how long is left and keep the control its normal colour.
