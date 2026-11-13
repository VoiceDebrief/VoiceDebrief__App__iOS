# The lab

*A brief. From the owner's voice memo of 13 November 2026, written up by the agent. Nothing here is built unless [what is built](../../built/index.md) says so.*

## The idea

VoiceDebrief for iOS started as one job: a voice note in, a transcript and a debrief out. In a day it gained on-device speech, an on-device model, vaults, signed commits and encrypted lanes, and it runs as one app on a phone, a tablet and a laptop, delivered by TestFlight. That combination is rarer than the product it was built for.

So for now the app is also a laboratory. The product that ships will be smaller and more focused. The lab exists to get the primitives and the key workflows right, and to find out what is possible, before deciding what that product is.

Because nothing here is being submitted to the App Store yet, the lab can ask for any capability Apple offers.

## What it should explore

| | Experiment | Question |
|---|---|---|
| L01 | One prompt, tools on and off | What does the on-device model do with a single tightly scoped prompt and a chosen set of tools? How reliable are its tool calls? |
| L02 | The model drives the screen | Can the model choose what the interface shows next, through function calls, from a state the code hands it? |
| L03 | The model edits a page | Can it write or change an HTML or JSON page in a vault that the app then renders? |
| L04 | Apple's larger model | The same prompts on Private Cloud Compute: what does 32,768 tokens and reasoning buy? |
| L05 | Another provider through the same framework | iOS 27 lets a session run on other models, Claude among them. What changes, and what does it cost in privacy? |
| L06 | Images | What can Image Playground and image input do for a note: a cover, a photographed whiteboard? |
| L07 | A file system for the model | A virtual file system over a vault, with access granted folder by folder |
| L08 | Graphs from notes | Semantic graphs from transcripts, linked across notes and vaults |
| L09 | Code inside the app | Can anything like a script run natively and safely on the device? |
| L10 | Many ways to show the same thing | Several interfaces for one workflow, compared on the three devices |

Each experiment is a screen in a Lab section of the app, with what was asked, what came back, how long it took and what it cost shown plainly. An experiment that fails is a result.

## Rules

- An experiment says what it is. Nothing in the lab is presented as a finished feature.
- Everything the model is given and everything it returns can be seen. See [Two decision engines](../two-decision-engines/index.md).
- What works is rebuilt properly, and probably moved out into its own app or package. The lab is where it is found, not where it lives.
