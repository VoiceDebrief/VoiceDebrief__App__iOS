# Where each key lives

*A position and a brief. From the owner's voice memos of 13 November 2026, written up by the agent. Decided by the owner the same day. None of it is built unless [what is built](../../built/index.md) says so.*

## The design in one paragraph

A passkey, behind Face ID, proves it is you. iCloud Keychain carries your secrets to your other devices, encrypted so that Apple cannot read them. Vaults hold the data, encrypted and version controlled, on a store that sees only ciphertext. Put together: sign in to the same Apple account on a new device, authenticate, the vault keys arrive, the app pulls the vaults, and the same files are there. The vault provides the synchronisation, and when two devices write at once it behaves as git does: the first wins, the second pulls, merges and pushes.

## Four keys, four homes

| Key | What it is for | Must it travel? | Where it lives |
|---|---|---|---|
| Vault keys, server tokens | Open and write vaults | Yes | iCloud Keychain, synchronised. **On by default** (owner's decision), with a switch to keep them on this device only |
| The user's key pair | Who you are: signs as you, lets others encrypt to you | Yes | iCloud Keychain to begin with; the master vault, opened by the passkey, when that is built. Never the Secure Enclave, which cannot let a key out and cannot hold an RSA key |
| The device's key pair | Which device, or which install of the app, did this | Never | The Secure Enclave of that device where it can be, otherwise the Keychain marked for this device only. Meant to be lost with the device or the app |
| Public halves | Checking the above | Freely | In the vault beside the data. The user's also in a register such as pki.sgit.ai |

Two details that follow:

- **A synchronised Keychain item cannot also demand Face ID.** That protection exists only for items that stay on one device. It is the main reason the passkey and master vault remain the end state: the passkey is behind Face ID every time, and the keys sit inside a vault rather than loose in the Keychain.
- **Keychain items survive deleting an app.** For the device key to die with the app, the app has to wipe it the first time it runs after a reinstall.

## Linking the device to the person

Every commit is already signed by a device key whose public half is in the vault. What is missing is anything that says whose device it is. The addition is a short statement in the vault, signed by the user's key: this device key is mine, from this date, for these uses. A reader then checks two things: the device signed the commit, and the person vouched for the device. Losing a device means withdrawing one statement and nothing else.

## Optionally, a person in the register

The app must work with no register at all. As an option, the owner can connect it to the identity he already has at [pki.sgit.ai](https://pki.sgit.ai), where his key pair is kept behind a passkey.

That site already has the flow, "Sign in with pki.sgit.ai", with no server in between:

1. The app makes a key pair and sends the person to `pki.sgit.ai/authorize/` with a request naming the app's public key, what it wants to do and for how long.
2. There, signed in with their passkey, the person reads who is asking and signs a delegation with their own key: this key acts for me at this site, for these uses, until this date.
3. The delegation comes back to the app, which keeps it and attaches it to what it signs.
4. Anyone can then check, against the register and starting from a root they trust, that the note was signed by a key a registered person vouched for. Withdrawing the link in the register ends it.

So without the extra step the app proves "the same device signed all of these". With it, the app proves "a person in the public register stands behind this device".

One thing to settle when building: that flow returns its answer to a web address on the asking site, so the app needs a page on its own site that hands the answer back to the app.
