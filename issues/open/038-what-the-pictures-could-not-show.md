# 038: What the pictures could not show

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the screens session (`work/screens`: `UITests/ScreensTests.swift`, `App/LaunchSample.swift`).

Finding 15, and the artefacts 16 to 20. Round 1 was limited by its own pictures.

- No picture of a confirmation. The app asks before sending, deleting and discarding; three users reported that
  it does not, because no picture shows it. Photograph each dialog (a test that taps the control, then shoots).
- Note screens are shown pushed under the Library tab. In the app, stopping opens the note on the Record tab.
  Show `note.working` there.
- The sample vault has a new random key in every launch, so its id, head and times differ between pictures of
  "the same" vault. Keep no key in the source, but make one sample world per run: write the sample folder once
  and let each launch reuse it (a path passed as a launch argument).
- Different pictures use different sample notes (3 in Settings, 4 in Library). Use one set, and say in the
  picture's name when a state is added.
- Not photographed: the Lab after a run, a vault that has a server, a recipient added by hand, the Identity
  screen with an identity, a failed recording, the "no language" state of the record screen.
- Settings in UserDefaults (the language, the vault chosen for saving) are not replaced in a sample launch.
- Portrait on iPad, and the largest text size on iPhone, where clipping is most likely.
- A second round after the fixes, with the same four users and the same tasks, so that findings can be marked
  fixed from a picture.

Round 2 done: the confirmations, a queued send, a queue of notes, recordings of the length they claim, and a note being made on the Record tab are pictured. Still to do: one sample world per run, the Lab after a run, a vault with a server, a recipient added by hand, an identity, portrait on iPad, the largest text size, and settings in UserDefaults.

Round 3 done: finish and send, the two lines of where the work happens in four states, the briefing, a sent note and the alerts are pictured. Added to what is still to do: the record screen just after "Finish and send" (its card), a send that failed, and a note saved to a vault by the app rather than by the sample.
