# What changed in v0.1.105

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

A fourth Lab experiment, L04, live labels, from the owner's voice note. While you speak, Apple's on-device model is asked every few seconds to fill in a small set of labels from the words so far: who the note is for (matched to a contact or an agent, with their avatar), its topic, title and urgency, and others you switch on. They appear as a grid of chips that update live. What you say a label is, stands: say this is a memo for the website conductor, or no, the topic is something else, and that label is pinned and the model can no longer move it; tapping a label does the same. After every loop a small notice says how long the model took to its first label and in all, about how many tokens were sent, and which labels changed, and every loop goes into a log that can be shared as JSON. You choose how often it asks and how many of the words it sends. The experiment keeps no recording and no note. In test: no loop has been run against a model, so its speed is not yet known.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
