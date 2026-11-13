# Release history

Every release of this repository. A push to `dev` whose `version` file names a version that has no tag yet is a release: CI tags it and publishes the site.

| Version | Date | What changed |
|---|---|---|
| v0.1.2 | 13 November 2026 | The debrief prompt, changed after the first real runs on an iPhone and a Mac: the model was copying quotation marks from the prompt's examples, renaming a heading, repeating a one-line note back as its own key point, and turning a passing remark into an action. The prompt now shows the shape with no quotation marks, says the speaker's own tasks are theirs, and says what is not an action. A note of fewer than 25 words is no longer sent to the model: the transcript is the whole note. |
| v0.1.1 | 13 November 2026 | The first feature, as the plan's quality spike: record a voice note or choose an audio file, transcribe it on the device with Apple's `SpeechAnalyzer`, and write a debrief with Apple's on-device model, reading a long note in parts. A diagnostics screen reports what the device says about both models and exports it. Nothing is saved yet. In test: nobody has judged the results on a device. Also: the TestFlight upload, proven by build 0.1.0 (4), installed on an iPhone and a Mac. |
| v0.1.0 | 13 November 2026 | The repository starts. An iPhone and iPad app that builds and tests, with one screen that says what is and is not built. The `SGitVault` vault engine copied from `PrompTugal__App__iOS`, with the door derivation made to work for any site and checked against the published vector. CI: build and test on a Mac, vault interop with `sgit`, and this site. The plan, published. |
