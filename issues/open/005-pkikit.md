# 005: PKIKit, the key bundle

**Status:** open. **Milestone:** 1.

One sgit-compatible identity: RSA-OAEP 4096 and ECDSA P-256 generation, the public bundle, fingerprints,
PKCS#8 export and import, envelope v2, detached signatures, sgit's passphrase-protected key store.
`PTLanes/LaneCrypto.swift` in `PrompTugal__App__iOS` is the seed (envelope, SPKI conversion, fingerprints).

Done when the interop job passes in both directions with `sgit pki`, and fingerprints match the five fixture
identities published by pki.sgit.ai.
