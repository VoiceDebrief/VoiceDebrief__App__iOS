# 005: PKIKit, the key bundle

**Status:** open. **Milestone:** 1.

One sgit-compatible identity: RSA-OAEP 4096 and ECDSA P-256 generation, the public bundle, fingerprints,
PKCS#8 export and import, envelope v2, detached signatures, sgit's passphrase-protected key store.
`PTLanes/LaneCrypto.swift` in `PrompTugal__App__iOS` is the seed (envelope, SPKI conversion, fingerprints).

Done when the interop job passes in both directions with `sgit pki`, and fingerprints match the five fixture
identities published by pki.sgit.ai.

## Done, 13 November 2026

`Apps/VoiceDebrief/Sources/Engine/PKIKit.swift`, as app code rather than a package for now. `pki-interop.yml`
passes in both directions with `sgit pki` (sgit-ai 0.27.0) and with pki.sgit.ai's `keys.js` (lib v0.2.28).

One line of the "done when" was not met as written: the five fixture identities were not found at
`pki.sgit.ai/directory/fixtures/` (404 on the day). In their place the unit tests check the fingerprints of
the register's real root record, and the workflow checks fingerprints of keys sgit and `keys.js` make in the run.
