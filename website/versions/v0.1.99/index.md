# What changed in v0.1.99

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

Fixes a crash on starting a recording (0.1.91 on the owner's iPhone, read from the TestFlight crash report): the live words' microphone tap is now put on cleanly, in the microphone's own format. And silent recordings: when no sound reaches the recorder for three seconds, the live words are stopped so the recording gets the microphone (every silent note so far was made while the live words ran). A new workflow reads the crash reports testers share.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
