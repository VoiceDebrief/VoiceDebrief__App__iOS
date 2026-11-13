# 004: Prove vault writes against the live server

**Status:** done, 13 November 2026.

Done, 13 November 2026: the owner created a vault from the app (build 0.1.5, on a Mac) on
`dev.send.sgraph.ai`; the app read it back with the commit's signature verified. That is the first live
write from the Swift engine. The same day `sgit` created and pushed a vault there with the owner's token.

Then the owner saved a debrief into that vault from the app: 4 files, one signed commit, compare-and-swap
on the ref, read back verified.

Not part of this issue any more: `sgit clone` of an app-made vault from the live server (see the reality file).
