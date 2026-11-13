# 031: Say what Send does, on the note

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the main session (`SendBar` in `RecipientsView.swift`).

Finding 3. Every note screen. Found by the privacy user (it decided them against the app), the driver and the
user who lost a recording.

The owner asked for the send bar (issue 026: sending is the point of a memo), and it stays. What the three users
could not tell from the screen: that pressing it asks first (it does), who "The developer" is, whether the audio
goes with the words, and where it goes. The bar is also shown on a note that was interrupted and on one with no
transcript. To a person who has not chosen a recipient, the largest control on a private note sends it to a
stranger.

To do, in order of cheapness: one line under or in the bar saying it asks first and what goes ("asks first;
sends the audio and the words, encrypted to their key"); name the built-in recipient as what it is on a test
build, in lower case ("the developer of this test build"); once a person has added a recipient of their own,
put that one first. Consider not offering the built-in recipient as the primary control until it has been used
once on purpose.
