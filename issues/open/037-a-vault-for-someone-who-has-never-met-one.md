# 037: A vault, for someone who has never met one

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the vaults session (`VaultsView`, `SaveToVaultSection`).

Finding 9, with 12. Screens `vaults`, `vault.detail`, `note.finished-end`. Found by three of four users.

The design says the Vaults tab "opens with what a vault is in three lines and one button", with the technical
parts behind "Technical". The tab opens with a list, a form and the words "random key", "signed commit",
"server", "token", and the two non-technical users took the end of a note ("Save this note to the vault ... as
one signed commit") to mean the note was not yet safe. What the privacy user could not find out:

- whether this note is already in a vault (the note says only "Kept on this device", while saving each finished
  note is switched on);
- whether notes saved automatically go to a server by themselves once the vault has one (they do not: say so
  where the server is chosen);
- that a server stores only what it cannot read (said in a footer on the Vaults tab, not on the vault);
- that the vault "On this device only" is a second copy on the same phone, not a backup.

Also: the address filled in for a new server ("https://dev.send.sgraph.ai", in the same dark text as a saved
row, directly under the saved server) reads as a second server; and "sgit clone followed by this key" gives no
command and is true only once the vault is on a server.

Round 2: unchanged. Added: the switch "Save each finished note to a vault" does not say where that vault is or whether one with a server sends by itself; neither a note nor the confirmation before deleting says whether the note is in a vault; no one place lists everything that can leave the phone, and backups are not mentioned.
