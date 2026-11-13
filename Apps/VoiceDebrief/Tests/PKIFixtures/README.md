# PKI fixtures

Three files the app's unit tests read (`PKIKitTests.swift`), through the checks in `PKIFixtureChecks.swift`.
They were made by the tools whose formats the app must match, not by the app:

| File | Made by | How |
|---|---|---|
| `pki-fixture-sgit.json` | `sgit pki` (sgit-ai 0.27.0) | `scripts/pki-interop/sgit_make.py`, run 1 of `pki-interop.yml`, 13 November 2026 |
| `pki-fixture-keysjs.json` | pki.sgit.ai's `keys.js`, `message.js`, `delegation.js` (lib v0.2.28) | `scripts/pki-interop/keysjs_make.mjs`, the same run |
| `pki-fixture-root.json` | pki.sgit.ai | the public record of the register's root, `https://pki.sgit.ai/id/sha256-db7f79fdd87e030a.json`, read the same day |

**They hold public material only.** The first two were passed through `scripts/pki-interop/public_fixture.py`,
which leaves out every private key, passphrase and sealed envelope. What remains is checked with public keys
alone: bundles, fingerprints, key codes, a detached signature, a signed statement, canonical forms, and a
sign-in request with its delegation and answer.

The checks that need a private key (opening sgit's passphrase-protected keys, opening an envelope, importing
WebCrypto's PKCS#8) run in `pki-interop.yml`, where sgit and keys.js make a new set on every run and Swift
reads it. That also means a change in either tool's format is noticed without these files changing.

To refresh them: take `sgit-made.json` and `keysjs-made.json` from the `made-by-sgit-and-keysjs` artifact of a
`pki-interop.yml` run and pass each through `public_fixture.py`.
