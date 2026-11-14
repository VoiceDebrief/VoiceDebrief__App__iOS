# 040: A way to say no in each confirmation

**Built (untried on a device): the three (send to the developer, delete a note, throw a recording away) are alerts now, which always show Cancel or Keep recording beside the destructive button.**

**Status:** open. From review round 2 (14 November 2026, `website/reviews/round-2/index.md`). **Owner:** the main session (`NoteDetailView`, `RecordView`, `SendBar`).

New finding 3. Screens `note.finished-send`, `note.finished-delete`, `record.recording-discard`. Found by three
of four users.

Each confirmation is pictured with one button: "Send the audio, transcript and debrief", "Delete the note and
its recording", "Throw it away". The code gives each a second button with the cancel role ("Cancel", "Keep
recording"), but on the iPhone simulator of iOS 26 a confirmation dialog is drawn as a small panel beside the
control and the cancel button is not drawn: a tap outside is the way out. Three users said they could not see
how to back out, and for "Throw it away" while recording that is the wrong moment to guess.

To do: check on a device whether the cancel button is shown. If it is not, use an alert, which always shows
both buttons, for the three that destroy or send something.
