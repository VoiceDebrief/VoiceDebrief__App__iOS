# 018: The user's key pair, the device key, and vouching (with issue 005)

**Status:** open: written and proven in CI, not yet run on a device. Decided by the owner, 13 November 2026.
See the article "Where each key lives".

A user key pair (sgit bundle: RSA-OAEP 4096 and ECDSA P-256) that travels through iCloud Keychain; a device
key that stays on the device (Secure Enclave where possible) and is wiped on reinstall; a statement in the
vault, signed by the user key, vouching for the device key. Optionally, a delegation from pki.sgit.ai
(`/authorize/`, kinds `pki.sgit.ai/authorize/v1` and `pki.sgit.ai/delegation/v1`) so that a registered person
stands behind the app's key. The app must work without the register.

## Where it stands (v0.1.9)

Built: `PKIKit` (issue 005, done), the Identity screen under Settings, the user's key pair in iCloud Keychain,
the device key, the vouching statement and its place in a vault, the sign-in request and the check of the
delegation that comes back. `pki-interop.yml` proves the formats against sgit and pki.sgit.ai's own code.

Left, and whose it is:

- **The owner, on two devices:** does the identity made on one appear on the other; does the device key say
  Secure Enclave on an iPhone; does a vouching statement get written to a vault and read back; does the round
  trip with pki.sgit.ai end with a delegation the app accepts.
- **The owner:** the automatic return from pki.sgit.ai. It needs the Apple team id, for
  `website/.well-known/apple-app-site-association`, and the Associated Domains capability on the app id
  `ai.voicedebrief.app`. Then: the entitlement `applinks:ios.app.voicedebrief.ai` (and `webcredentials:` for the
  in-app sheet) in `VoiceDebrief.entitlements`, and `PKIDelegation.returnsToTheApp` set to true. Until then the
  answer is pasted in.
- **The session that owns `VaultBook`:** issue 025, so that debriefs are signed by the device key.
- Not started: walking the register's links from the pinned root for an issuer that is not the root; a
  "strong" delegation (listed in the issuer's record today); withdrawing a vouching statement.
