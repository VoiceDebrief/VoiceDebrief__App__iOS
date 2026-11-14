# 035: A readable width on iPad

**Built for this session's screens and the finished sessions' (library, note, settings, diagnostics, about, recipients, words, lab, credit, identity): a readableWidth() modifier, 720 points, centred. Not yet: VaultsView (the vaults session), file paths breaking at a slash.**

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the main session for the shell and the note, library and settings screens; the vaults session for `VaultsView`.

Finding 7, with 14. Every list on iPad: `library`, the note screens, `vaults`, `vault.detail`, `settings`,
`diagnostics`, `about`, `credit`, `recipients`.

In landscape on iPad a list runs from one edge of the detail column to the other, about 1,150 points, with a
label at the far left and its value at the far right. Only the record screen holds its content to a readable
width, as the design asks of every screen ("so that a wide window is not a stretched phone").

To do: one modifier, used by every list, that holds content to a readable width and centres it; file paths in
a vault should break at a slash, not in the middle of a name.

Round 2: fixed for a note, the Library and Settings. The Vaults screens remain.
