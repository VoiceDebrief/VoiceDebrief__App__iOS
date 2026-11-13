# 102: Prove the app's large-file exchange against the live server

**Status:** open.

The upload in parts and the download in ranges are tested in CI against a folder, and sgit's own exchange was run against `dev.send.sgraph.ai`. The Swift code has not spoken to the server. First run on a device: add a video over 100 MB, clone the vault with `sgit` on a computer and compare; open it in the web Vault UI; read a file `sgit` pushed.
