# 118: sgit app: the web Vault inside the app, and its features natively

**Status:** open. **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

The owner, 14 November 2026: recreate as much as possible of the web Vault's core here (navigate folders, open a
file, edit a file, see the HTML preview), and "allow me to open the full web interface here", loading the vault by
JavaScript as sgit.ai's embedding does, not by putting the key in the address.

**Written (14 November 2026, not yet compiled):** `UI/WebVaultView.swift`. The protocol it uses was tried against
the live page first, in Chromium, with a throwaway vault: see the reality file's row.

**What the try showed, to keep:**

- `https://dev.vault.sgraph.ai/en-gb/vault/?embed=1`, loaded as the page itself (no frame), posts
  `{sg: 'vault-embed-ready'}` to its own window; a posted `{sg: 'vault-open', key, mode: 'vault', deepLink}`
  opens the vault; it answers `{sg: 'vault-ready', vaultName, fileCount}`. A file's path as `deepLink` opens on
  that file.
- The key is not stored by the page. `sg-vault-recent` is written to local storage; the app's web view keeps no
  storage after it closes.
- An event `vault-settings-access-key` on `<vault-shell>` with the access key turns the page writable. This is the
  page's own internal event, not a documented interface: it may change.
- `vault.sgraph.ai` (production) answered nothing. The app uses the dev host.

**Left:**

- Nobody has run it on a device. First things to look at: the page's layout on a phone, downloads ("Save"), and
  whether its HTML preview works in a web view.
- With changes allowed, the web Vault's commits are unsigned and it pushes without checking that nobody else
  pushed first; it also rewrites a folder without the `large` mark. So: off by default, a warning, and not offered
  where a vault has large files. The proper fix is in the web Vault.
- The vault's name is "Untitled Vault" there: the app's name for a vault is local.
- Natively: a simple edit of a text file, and an HTML preview (a sandboxed web view fed from the vault). Not
  started; the web Vault inside the app covers both meanwhile.
- A picture: the screen needs the network, which the picture harness does not have.
