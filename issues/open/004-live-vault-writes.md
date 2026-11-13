# 004: Prove vault writes against the live server

**Status:** open, half done.

Done, 13 November 2026: the owner created a vault from the app (build 0.1.5, on a Mac) on
`dev.send.sgraph.ai`; the app read it back with the commit's signature verified. That is the first live
write from the Swift engine. The same day `sgit` created and pushed a vault there with the owner's token.

Still to do: a commit to an existing branch from the app (saving a debrief), which exercises
compare-and-swap on the ref; then `sgit clone` of that vault on a computer.
