# 011: Vaults are local first; a server is a remote

**Status:** open. Corrects something wrong today. See the article "The vault is a version-controlled store".

The Vaults tab asks for an access token before creating a vault. Creating a vault needs no server. Create
and use vaults on the device (the engine already writes to a folder, `FolderVaultTransport`); add servers as
named remotes with an address and a token; push and pull explicitly.
