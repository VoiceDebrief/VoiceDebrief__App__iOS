# SGitVault test fixtures

THROWAWAY test vaults. Their keys (in each `expected.json`) were created for these
tests only. The vaults exist on no server and hold nothing but the test text.

| Fixture | Vault id | Format | What it covers |
| --- | --- | --- | --- |
| `plain/` | `fixtplain1` | 1 (12-hex object ids) | tree walk, nested folders, a unicode file name, two named branches (`current`, `device-ipad`), signed commits |
| `deflate/` | `fixtdefl1` | 2 (`ids-128`, `blob-deflate`) | 32-hex object ids beside 12-hex ones, one `\0sgz1` deflated blob (`docs/big.txt`) |

`<fixture>/server/bare/…` is exactly what `https://dev.send.sgraph.ai/api/vault/read/<vault id>/<path>`
would return: it is written by sgit-ai 0.27.0 itself, pushing to its in-memory server.

- `generate_fixtures.py <dir>` makes new fixtures (`pip install sgit-ai==0.27.0`). New fixtures have
  new random IVs, timestamps and signing keys, so every object id changes; commit them together.
- `reference_reader.py <dir>` reads every fixture with only HMAC, HKDF, AES-GCM, SHA-256, zlib and
  ECDSA, checks every object id, size, content hash and commit signature, and compares the files
  with `expected.json`. CI runs it on Linux.
