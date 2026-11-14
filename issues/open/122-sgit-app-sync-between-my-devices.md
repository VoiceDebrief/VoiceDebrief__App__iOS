# 122: sgit app: the same vaults on every device, without setting anything up

**Status:** open. **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

The owner: "the synchronisation between devices ... has to be completely transparent and straightforward".

To do: the list of vaults and their keys, and the access key, in iCloud Keychain (synchronisable items, as
VoiceDebrief did in issue 017), with a switch to keep them on this device only; pull when the app opens and comes
to the front, push after each change, and say so on the vault's standing line. Each secret is its own file, so two
devices changing different secrets do not conflict; the same secret changed on two devices keeps both and asks.
Needs an access key to reach the server; without one a vault stays on the device it was made on, and the app says
so. Mac, iPad and iPhone are the same app.

**Written (14 November 2026, not yet compiled):** see the reality file's row. Left: push after each change is what every write already does (a commit is pushed); a pull on a timer while the app is open; the same secret changed on two devices at once is decided by the server's compare-and-swap (the second write is retried on the newer head, so the later change wins and the earlier stays in history), not yet shown to the person.
