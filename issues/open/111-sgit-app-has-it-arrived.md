# 111: sgit app: say whether a file has arrived

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Finding 2. Screens `vault`, `vault.folder`, `vault.list`. Found by the teammate, who could not finish "be sure
they arrived".

No screen says whether what is shown is the latest, or whether something just added has reached the server. The
design says a file is never shown as in the vault before its commit is pushed and read back; the pictures show
only a vault at rest, so a person cannot see the difference between "added" and "arrived".

To do: a line on the vault that says where it stands ("everything here is on the server, checked a minute ago";
"3 of 21 on their way; keep the app open"), a mark on a file that is still on its way, and a plain end ("21
files added and on the server"). "Refresh" is behind the three dots; pulling down should do it.

**Done (14 November 2026, green in CI and in the pictures of that run):** a line at the top of every folder of a
vault says where it stands: on the server and when that was last checked, on this device only, how many files
are on their way in ("keep the app open"), or that some did not go in and are kept. Pulling down refreshes.

**Left:** a mark on a single file that is still on its way (a file is not listed at all until its commit is
pushed and read back; the upload card names it); a plain last line when a batch ends ("21 files added and on
the server"); a picture of a vault that is not at rest (issue 116).
