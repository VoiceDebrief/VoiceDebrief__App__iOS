# 112: sgit app: who added it

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Finding 3. Screens `history`, `commit`. Found by the editor and the teammate.

History and a commit say when and what. Who is a key id, a fingerprint and "This device's key" or not; the
commit screen says itself that nothing in the vault ties a key to a name. For a team's photos, "who took these"
is the first question.

To do: let a device name itself once (a name kept with its public key in the vault, as VoiceDebrief's Identity
does for a device), show that name in History and beside a file, and say "this device" in words. Group History
by day.

**Written (14 November 2026, not yet compiled):** History is grouped by day, and each commit says "This device"
or "Another device (key ...)" in place of a hash; the hash stays on the commit's own screen.

**Left, and it needs a decision first:** a name for a device. A name has to live in the vault to be seen by the
others, which is a change to what a vault holds, read by the `sgit` command and the web Vault UI as well as this
app. Proposed: one small file per device beside its public key (the key id, a name the person chose, signed by
that key), written the first time the device adds to a vault, so that a name cannot be claimed for somebody
else's key. To agree with the owner and the sgit side before anything is written; until then a commit can only
be told apart as this device or another.
