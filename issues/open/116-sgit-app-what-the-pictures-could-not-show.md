# 116: sgit app: what the pictures could not show

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Finding 15. The pictures themselves (`sgit-app-screens.yml`, the app's sample vault).

Round 1 read twelve screens, each at rest. Not pictured, and each was a place a user stopped or guessed:

- the Create sheet as a person meets it first, with no access key, and a vault that is on this device only;
- what the plus and the three dots open;
- the photo picker's result: files on their way, a count, a large video in parts, one that failed and its retry;
- a key shown, with its copy button, its link and its QR code;
- a video opened; a file too large to preview;
- an error: a wrong key pasted, no network, a refused write for want of an access key;
- dark appearance, and the largest text size.

A second round should follow the fixes for issues 110 to 115, with the same three users and tasks.

**Done (14 November 2026, green in CI on `50c8629` and looked at):** four more pictures, 17 in all: the Create sheet with no access key
(`create-nokey`), a vault on this device only (`vault.local`), files taken in and waiting to be sent
(`vault.adding-adding`), the vault key shown with its copy button, link, QR code and command (`share.key`).

**Left:** the menus open; a failed upload and its retry; a video opened; the errors; dark and the largest text;
round 2 of the review.

**Done after that (14 November 2026, green on `d2cb5ce` and looked at):** an eighteenth picture, `vault.adding-refused`: a
file added by somebody with the vault key and no access key, refused by the app's own check, with what it says
and "Try again" (the state issue 110 is about).

**Written after that (14 November 2026, not yet compiled):** four more, 22 in all: the vault and the shown key in
dark appearance, the vault and the share sheet at a large accessibility text size.
