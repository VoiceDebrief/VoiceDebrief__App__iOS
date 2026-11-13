# 018: The user's key pair, the device key, and vouching (with issue 005)

**Status:** open. Decided by the owner, 13 November 2026. See the article "Where each key lives".

A user key pair (sgit bundle: RSA-OAEP 4096 and ECDSA P-256) that travels through iCloud Keychain; a device
key that stays on the device (Secure Enclave where possible) and is wiped on reinstall; a statement in the
vault, signed by the user key, vouching for the device key. Optionally, a delegation from pki.sgit.ai
(`/authorize/`, kinds `pki.sgit.ai/authorize/v1` and `pki.sgit.ai/delegation/v1`) so that a registered person
stands behind the app's key. The app must work without the register.
