# What changed in v0.1.34

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

The sgit app: a vault is created on the device with no access token and no network, and takes files at once; sharing it sends it to the server, which is the first time a token is asked for. Forgetting a vault that is only on the device warns that it deletes it. In the engine, `VaultSync` can move a vault that holds large files. At the owner's request after the first run: the access key can be typed on the Create screen and the new vault goes to the server at once; files and folders can be dropped in from the desktop and dragged out; on an iPad or a Mac the folders are a tree down the left.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
