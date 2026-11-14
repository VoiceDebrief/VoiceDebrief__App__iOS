# 110: sgit app: a teammate sent a vault key cannot add to it

**Status:** open. From the sgit app's review round 1 (14 November 2026, `website/sgit-app/reviews/round-1/index.md`). **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

Finding 1. Screens `settings`, `add`. Found by the teammate and the family organiser, and checked in the code.

A colleague sends a vault key. With it the app opens the vault and reads it. Adding a photo to a vault that
lives on the server also needs an access key, and without one the write fails ("writing to it needs an access
key. Add one in Settings"). Nothing on the add sheet says so, the person was sent one string, and no screen says
where an access key comes from. The app's first job, in the owner's words an easy way for the team to share
photos and large videos, stops at the first photo for everyone but the person who made the vault.

To decide, with the owner: how a teammate comes by the right to write. Either the access key travels with the
invitation (and the share sheet says so), or the person who shares gives each teammate one, or the server learns
to accept a write from anybody who holds a vault's write key. Until then, say it at the moment it matters: on
the add sheet when the key is a vault key, and where the plus is tapped, with what to ask the sender for.
