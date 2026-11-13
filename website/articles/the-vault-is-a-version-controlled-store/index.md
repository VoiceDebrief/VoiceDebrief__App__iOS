# The vault is a version-controlled store

*A position and a brief. From the owner's voice memo of 13 November 2026, written up by the agent.*

## The position

A vault is usually described by its encryption. That undersells it. A vault is a version-controlled data store: files, history, branches, signed commits. The encryption is one property; the history is another, and for an ordinary application it may be the more useful one. Anything an app keeps could be kept this way and gain history, integrity and a way to move.

And a vault is a good way to move data. Two devices, two people or a person and an agent can exchange work by exchanging vaults, or by writing to each other's lanes.

## The correction

The first vault screen in this app asks for an SG/Send access token before it will create a vault. That is wrong in principle. **Creating a vault needs no server and no token.** A vault can exist on the device alone. A token is needed only to push it to a server, and the server itself should be something you configure, not something assumed.

So:

- **A vault is local first.** Create, commit, read and browse with no network.
- **A server is a remote.** Add one, with its address and its token, when you want the vault elsewhere. Push and pull are explicit.
- **Some things need a remote.** A lane, where others write to you, lives on a server. That is one use, not the definition.

## The brief

| | What |
|---|---|
| Local vaults | Create and use a vault on the device with no token. The engine already writes to a folder in its tests; the app should use that |
| Remotes | A list of servers, each with an address and a token in the Keychain. A vault may have none, one or several |
| Several vaults, several lanes | Register them with names. Choose where a note goes: one vault, several, a lane to a person or to an agent that conducts other agents |
| A file system | The vault as a virtual file system the app, and later the model, can be given in part: this folder, read only |
| Vault apps | A vault can hold an app: pages and data rendered from the vault. Render them here. Then create and edit them here, and see whether the model can |
| Graphs | Every note processed into the store, then linked: semantic graphs across notes and across vaults |

## Order

Local vaults and remotes first, because they correct something that is wrong today. Then several named vaults and lanes, which the recording workflow needs. The file system, vault apps and graphs are [lab](../the-lab/index.md) work.
