# 004: Prove vault writes against the live server

**Status:** open, blocked on an SG/Send access token (as a CI secret, never in the repository).

`SGitVault`'s writes are proven against sgit's in-memory server and read back by `sgit`, never against
`dev.send.sgraph.ai`. Until this passes, vault sync is unproven, not merely unfinished.
