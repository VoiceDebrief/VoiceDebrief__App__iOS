# 103: The sgit app after milestone one

**Status:** open. In order: adopt local-first vaults and remotes (011) and iCloud Keychain (017); a share extension; background uploads (a background URLSession fed from the staged ciphertext); a file-level merge; branches; video thumbnails and streaming.

## 14 November 2026

The owner's first run hit the token on Create. Done in answer: a vault is created on the device with no token, takes files there, and is sent to the server from Share (`VaultShelf.sendToServer`, `VaultSync.transferWithLargeFiles`). After that it lives on the server.

Not done, and why: keeping a shared vault on the device with push and pull, as VoiceDebrief does. Two people adding photographs at the same time would diverge and the engine has no merge; and a pull would fetch every video. Both come before that.
