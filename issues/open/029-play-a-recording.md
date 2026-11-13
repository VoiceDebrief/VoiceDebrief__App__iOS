# 029: Play a recording, and show how long an interrupted one is

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the main session (`NoteDetailView`, `NoteParts`).

Finding 1. Screens `note.interrupted`, `note.finished`. Found by the user who lost a recording elsewhere and by
the driver; it decided the first against the app.

An interrupted note says "The recording is kept" and offers no way to play it and no length. A finished note has
no player either. A person who has lost a recording does not believe a sentence; they believe hearing it.

To do: a player on every note that has audio (the design's build B), and for a note with no transcript at least
the audio's length and size, so that "kept" can be checked. Playing a note's audio is listed as proposed in the
reality file; this finding is the case for doing it before anything else on the note screen.
