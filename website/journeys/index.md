# Journeys: three people, from opening the app to knowing where things are

Three people arrive at the apps for different reasons. For each: what they want, the way through as the apps are today, where they get lost, and what the Guide does about it. Written by the Sherpa session, 14 November 2026. What exists is the [reality file](../built/index.md); where each idea stands is [Ideas](../ideas/index.md); how each screen works is in the [guides](../guides/index.md).

## 1. The owner, after a night of builds

**Wants:** to wake up, open the app and know what was made overnight, what to try, and where each of the ideas spoken into voice notes now stands. In the owner's words: "I wake up and I go, okay, what has been created? I just do not know where to go."

**The way through, today:**

1. Install the new build from TestFlight and open it. The Record tab shows the briefing card: "Updated to this version: see what is new", and what happened to the notes since the last opening ([guide](../guides/briefing/index.md)).
2. Open **Guide** (written; reachable once it has its place in the sidebar), then **What is new**. Every version since the last look is marked New, newest first, each with its notes and a link to its page with pictures of what changed.
3. Back in Guide, the status counts: seen working, built untried, in progress, proposed, parked. **Built, untried** is the morning's list: things that exist and wait for a person on a device.
4. Search **Ideas** for a word from a voice note ("inbox", "QR", "speaker"): each idea says its status, the sentence that decided it, where it is in the app and which versions named it.
5. Open the guide for a feature to find the button: a picture of the screen with numbered arrows.

**Where it can still go wrong:** the statuses are only as current as the issues and the reality file when the build was made; a session that builds something and does not update its issue leaves the idea a step behind. The rule is the repository's own: the reality file is updated in the same commit as the code.

## 2. A new tester, sent a TestFlight invitation

**Wants:** to know in a minute what the app does, try the one thing it is for, and not lose anything.

**The way through, today:**

1. First launch: the welcome (written, and shown once it is attached to the app's shell) says what the app does (a voice note in, a transcript and a short debrief out, on this device), what to try first (record ten seconds and finish) and where things are (four tabs and the Guide).
2. Choose the language spoken, if it is not the one shown (the globe on the Record tab, or Settings).
3. Tap the record button, speak, tap again. The note opens and fills in: transcript, then the debrief ([guide](../guides/record/index.md)).
4. Open the note: play it, read the debrief, share the recording ([guide](../guides/note/index.md)).
5. Optional, for later: a vault, a recipient, the identity. Each has a guide, and each idea's status says whether anyone has seen it work.

**Where they get lost:** the top bar's balance (test credit, no money is taken), the word vault before anyone has explained it (issue 037), and sending to the developer, which is built into a test build. The welcome names the first two; the recipients guide names the third.

## 3. A teammate who was sent a vault

**Wants:** to open what a colleague shared and, often, to add to it. They were sent one string and have never heard of sgit.

**The way through, today:**

1. Install SGit Vaults, paste or scan what they were sent: the vault opens and can be read.
2. Adding a photo to a vault that lives on a server also needs an access key, separate from the vault key. The app says so when a write is refused, and who to ask (v0.1.45). How a teammate should get that right is the owner's decision ([issue 110](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/110-sgit-app-a-teammate-cannot-add-without-an-access-key.md), parked).
3. Whether a file has arrived is said on every folder (issue 111, in progress).

**Where they get lost:** at the first photo, without an access key; and at the word key, of which there are four. The sgit app's own [review](../sgit-app/reviews/round-1/index.md) found both. The Guide for SGit Vaults is the next piece of this work: the same Ideas list already covers its issues (filter by app).

## What the Guide is for, in one line each

| Who | First screen | Then |
|---|---|---|
| The owner | Guide, What is new | Ideas, filtered to built untried |
| A new tester | The welcome | The record guide |
| A teammate sent a vault | SGit Vaults' own first screen | Ideas, filtered to SGit Vaults |
