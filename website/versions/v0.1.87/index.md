# What changed in v0.1.87

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

A fix in the Lab's control centre, found while looking for why three notes from 0.1.72 arrived as silence. Its Listen switched the shared audio session off when it stopped, a moment after the screen was left: if a note was being recorded by then, or already was when Listen was pressed, that could switch the microphone off underneath the recording. A Listen still waiting for the microphone permission could also start after the screen had gone. The Lab now never switches the audio session off, does not listen while a note is being recorded, gives up a start that was overtaken by a stop, and stops when the app leaves the foreground. Whether this was the cause of those three notes is not known.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
