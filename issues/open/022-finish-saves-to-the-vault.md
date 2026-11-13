# 022: Finishing saves to the vault; discarding is the awkward path

**Status:** open. Decided by the owner, 13 November 2026. Answers open question 1 of the design.

Unless the user cancels, a finished note is saved to the vault. No button to remember.

The control that ends a recording is green and says what happens: finish, process, save. The red control is
only for throwing a recording away: placed away from the thumb, and taking two presses (or a held press) so it
cannot be done by accident.

Needs: a default vault (011, 014); a queue for saves made with no network; audio over 3.8 MB (006): the
owner's 6 min 44 s note was 1.7 MB, so the limit is about a quarter of an hour.
