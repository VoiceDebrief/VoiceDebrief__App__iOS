# 114: sgit app: getting a folder out, at full quality

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Findings 7 and 8. Screens `vault.folder`, `file`, `share`. Found by the editor, whose task it was.

A file leaves one at a time, by Share or by Save to Photos, and nothing says either hands over the original
(Photos may re-encode a video). There is no way to take a folder. The route that gives everything, the `sgit`
command on a computer, is named on the share sheet with no command to copy and no address. A read key does not
open in the web Vault UI, so somebody on a laptop who should only look needs this app or the command line.

To do: select several, or "Save this folder to Files", with the size and a count; say "the original, as it was
added" where that is true; on the share sheet, the exact line to paste on a computer; for the Mac, the app
itself is the answer once it runs there (the design says iPhone, iPad and Mac).

**Compiles and its tests pass (14 November 2026, `50c8629`); done when somebody has saved a folder on a device:** the three dots
on any folder offer "Save these N files to Files" with the size; the app fetches each, lays them out as in the
vault and hands the folder to the Files app. The file screen says Open and Share hand over the original, byte for
byte. Beside the shown vault key, the line to paste on a computer (`pip install sgit-ai && sgit clone`), with a
button that copies it with the key in it.

**Left:** selecting several files that are not one folder; a read key in the web Vault UI (not this app's to
fix); the Mac.
