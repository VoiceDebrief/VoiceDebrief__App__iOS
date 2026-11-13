# 036: States that say what to do next

**Built (untried on a device): row states say what to do or why; an untranscribed note is "Voice note, not yet transcribed"; a cut title ends with an ellipsis; Recent says the day; Settings says "as you speak" and that an interrupted note is saved once run again; the promise is on the record screen before recording; the language is named; "1 line". Not done: Diagnostics' "Machine" line (check what a device shows).**

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the main session (`NoteRow`, `RecordView`, `SettingsView`, `DiagnosticsView`).

Finding 8, with 13 and 14. Screens `record`, `library`, `settings`, `diagnostics`, note details.

Small things that left a user without a next step or with a wrong reading:

- "Not finished" and "Transcript only" on a row explain nothing. The first needs "interrupted: open to run it
  again"; the second needs to say the note was too short to summarise, or that the model was not available.
- "Recent" on the record screen shows a time and no day: yesterday's interrupted note reads as today's.
- An interrupted note is titled "Recording", which on the record screen reads as something happening now.
- A title is the first twelve words with nothing to mark the cut, and on an iPhone a row's title is cut mid-word
  and its state wraps onto a third line.
- "Save each finished note to a vault" is silent about a note that was interrupted.
- "Every recording is kept on this device the moment it stops" on Settings; the recording screen says "as you
  speak", which is the stronger and truer sentence.
- No promise before recording: "saved as you speak" appears only once a recording has started.
- The language is "en-GB" on Settings and in the toolbar, and "English (United Kingdom)" on a note.
- "1 lines" under Transcript. "Machine arm64" on Diagnostics is not a device model on a simulator; check what a
  device shows.
