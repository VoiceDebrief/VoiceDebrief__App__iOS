# 016: Pictures of every screen, and synthetic users

**Status:** open. See the article "Synthetic users".

Carry over `screens.yml` from `PrompTugal__App__iOS`: one XCUITest per screen with sample data, PNGs for
iPhone and iPad. Then synthetic users walking them. The screenshots are also how the agent sees its own work.

## Progress

- **Stage 1, pictures: done.** `screens.yml`, the UI test target `VoiceDebriefUITests`, the scheme
  `VoiceDebriefScreens`, and the launch arguments `-VDSampleData` and `-VDScreen`. Run 1 produced 68 pictures
  (17 screens, iPhone and iPad, light and dark). How to fetch them: `website/develop/index.md`, "Seeing the screens".
- **Stage 2, synthetic users: round 1 done.** `website/reviews/round-1/index.md`: what is plainly wrong, four
  users, 21 findings (15 open, 6 artefacts of the pictures), issues 029 to 038. Round 2, and what the pictures
  could not show, are issue 038.
- **Round 2 done** (14 November 2026): `website/reviews/round-2/index.md`. Three of round 1's open findings fixed,
  six in part, six unchanged; two of four users changed their minds; twelve new findings, issues 039 to 041.
- The Lab's two screens (`lab`, `lab.prompt`) were added when the Lab reached `dev`. Adding a screen is four
  small edits, listed on the develop page.
