# 115: sgit app: the Create sheet, the four keys, and smaller things

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Findings 9 to 14. Screens `create`, `vaults`, `add`, `settings`, `vault`, `file`, `history`, `commit`.

- **Create.** The first screen says a vault you create "needs no account, no access key and no network"; the
  Create sheet shows a server switch that is on and an access key. Say on the sheet what the switch costs, and
  let its default be off for a person with no access key. "A new vault is a random key, an empty folder and one
  signed commit" should not be the first sentence. "Name, for this device only" left two users unsure what name
  others see: say that others name it themselves.
- **Four keys**: vault key, read key, access key, this device's signing key. "Add a vault by its key" does not
  say which; the add field offers three kinds at once. One line each, where each first appears, and a different
  word for the access key, which is not a key to a vault.
- **A vault's row** is an id, an access level and a server's name in typewriter text. "Shared, you can add" or
  "Only on this phone" says what a person needs.
- **The plus and the three dots** carry no words; Share and History are both behind the dots.
- **"Remove the access key"** is red and says nothing of what follows.
- **"Convert to JPEG and H.264 when adding"** is explained by format names; say which choice lets a colleague
  see the photo in a browser.
- **iPad**: lists as wide as the window; tiles phone-sized in a wide window.
- **Small**: a photo needs a second tap to fill the screen; "The decrypted copy is in this app's cache" reads as
  a warning; a commit's title is a hash; a grid in one folder and a list in another with no visible switch.

**Done (14 November 2026, green in CI and in the pictures of that run):** the Create sheet's switch is off for a
person with no access key and the sheet says what turning it on needs; the name is said to be for this device,
others name the vault themselves; a vault's row is in words ("Shared: you can add and change", "Only on this
device").

**Left:** one line for each of the four keys where it first appears and another word for the access key; words
on the plus and the three dots (Share is out of the dots, History is not); "Remove the access key"; the
conversion switch; iPad widths; the small things.

**Done after that (14 November 2026, green on `86f0150`, seen in the pictures):** "Add a vault you were sent" in place of "by its
key"; Settings says what the access key is (a pass from whoever runs the server, which opens no vault) and what
removing it does; the conversion switch is "Make photos and videos open in any browser".
