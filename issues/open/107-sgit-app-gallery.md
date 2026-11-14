# 107: A gallery of vaults, opened in a browser inside the app

**Status:** open. Asked for by the owner, 14 November 2026, to demonstrate vaults to people, including outside testers.

Built: a Gallery screen reached from the list of vaults. Entries have a name, a line about them, a topic and a link; they are grouped by topic and can be searched. An entry opens in the web Vault in the system's browser inside the app. An entry that carries a key this app can open has "Add to my vaults".

The list is data, never code, because a link may carry a key and no key is committed:

- entries added on the device, by pasting or scanning a link, kept in the Keychain;
- a file `showcase.json` at the top of any vault on the device: `{"v": 1, "entries": [{"name", "description", "topic", "link"}]}`.

The gallery ships empty and says how to fill it.

## Needed from the owner

One of:

1. **A showcase vault** (preferred): a vault with `showcase.json` at its top, and its key added to the app on each device that should show the gallery. Changing the file changes every device's gallery.
2. The links themselves, to be pasted into the app.

For each vault to be shown: a name, one line, a topic, and a link that opens it in the web Vault. For anything shown to outside testers the link should be read-only: a read-only token from the web Vault's token manager (`ro-word-word-1234`, which can be revoked) or a read key. A vault key lets whoever sees it change the vault.

## Not known yet

- Whether the web Vault opens from the links the app builds, inside the in-app browser: by its source it should (the site's root followed by `#` and the key or token). Never tried.
- Which address the owner's vaults are on. The app builds links to `vault.sgraph.ai`; the owner's screenshot shows `dev.vault.sgraph.ai`. A full link in `showcase.json` avoids the question.
