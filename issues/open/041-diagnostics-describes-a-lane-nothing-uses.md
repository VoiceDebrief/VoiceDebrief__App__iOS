# 041: Diagnostics describes a pasted lane that nothing uses

**Status:** open. From review round 2 (14 November 2026, `website/reviews/round-2/index.md`). **Owner:** the main session (`DiagnosticsView`, `NoteParts`).

New finding 2. Screen `diagnostics-end`. Found by the privacy user and the developer, and checked in the code.

The "Lane" section on Diagnostics has a field for an `sgi1.` lane link and says: "After each run a button can
send that note, encrypted, to the developer's lane ... This build has a lane built in; a link pasted here is
used instead." Since recipients arrived (issue 019) a note is sent from the send bar to a recipient.
`DeveloperLane.current(pasted:)` is read only by `DeveloperLaneSection`, and nothing shows that section any
more. So the pasted link changes nothing, and the screen says the app does something it does not, which the
reality discipline forbids. The privacy user read it as a way for the destination of "Send to the developer" to
change silently.

To do: remove the field and the sentence from Diagnostics (the place to add a destination is Recipients), keep
the built-in lane's vault and key fingerprint there as facts, and delete `DeveloperLaneSection` if nothing uses it.
