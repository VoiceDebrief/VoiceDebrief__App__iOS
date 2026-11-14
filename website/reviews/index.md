# Reviews

Rounds of looking at the app as it is, from pictures. The app is written by agents that cannot run it, so [CI photographs every screen](../develop/index.md) from invented sample data, and each round here is somebody reading those pictures: first the agent that made them, then a panel of [synthetic users](../articles/synthetic-users/index.md), each with a purpose, a level of knowledge and only the screens they would see.

A finding is where a user's expectation and the next picture disagree, or where a user stopped. Each finding names the screen, who found it, the session that owns that screen, and a status:

| Status | Meaning |
|---|---|
| open | Written down, with an issue under `issues/open/` if it is worth fixing |
| fixed | Changed in the app, and seen to be changed in a later round's pictures |
| not a fault | An artefact of how the pictures are made, or a decision that stands. It says which |

A synthetic user reads a picture. It cannot feel a control that is too small, hear nothing, or drive a car, and it has been wrong about what a tap would do. The owner on a device remains the test that counts; a round is a cheap way to find what to look at.

## Rounds

| Round | Date | Pictures | Findings |
|---|---|---|---|
| [Round 2](round-2/index.md) | 14 November 2026 | 33 pictures per set, at commit `4338ea2` on `work/screens` (`dev` up to `6475ff7`) | Of round 1's 15 open findings: 3 fixed, 6 fixed in part, 6 unchanged. Two users changed their minds. 12 new findings; issues 039 to 041 |
| [Round 1](round-1/index.md) | 13 November 2026 | 28 pictures per set, iPhone and iPad, light and dark, at commit `fb0c548` on `work/screens` | 21, of which 15 open and 6 not a fault; ten issues opened (029 to 038) |
