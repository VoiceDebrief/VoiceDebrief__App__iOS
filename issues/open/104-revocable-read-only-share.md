# 104: A read-only share that can be taken back

**Status:** open. A question for the owner.

A vault key and a read key cannot be revoked. The web Vault UI's token manager has a read-only token with an expiry and a revoke (`ro-word-word-1234`, a small encrypted record held as a transfer on the server), marked there as a test harness. sgit has no equivalent. Agree one format for the app, sgit and the web UI before building it in the app.

## The web Vault's read-only token, as its source has it (read 14 November 2026)

From the Send repository at `da293d4`, `en-gb/vault/token/vault-token-manager.js` and `lib/sg-vault/sg-vault-crypto.js`. Enough to build it natively; the open question is still whether this is the format to keep.

- The token is `adjective-noun-NNNN`; `ro-` is only a prefix in links.
- Its record lives on the server as a transfer whose id is the first 12 hex of `sha256("ro-token-transfer-v1:" + token)`.
- The record is `iv(12) + AES-256-GCM` of `{"vault_id", "read_key" (base64 of the 32 bytes), "ref_file_id"}`, under PBKDF2-SHA256(token, salt `sgraph-ro-token-v1`, 100,000 rounds).
- Create: `POST /api/transfers/create` with the access key and `{file_size_bytes: 0, transfer_id, delete_auth_hash, max_downloads, auto_delete: false, expires_at}`, then upload the ciphertext, then `POST /api/transfers/complete/{id}`.
- Open: `GET /api/transfers/download/{id}`, no access key, then decrypt; the vault is read from `bare/refs/<ref_file_id>` with the read key.
- Revoke: `DELETE /api/transfers/delete/{id}` with the header `x-sgraph-transfer-delete-auth` holding the preimage of `delete_auth_hash`.
- The owner's list is a file in the vault, `.vault/owner/readonly-tokens.json`, encrypted a second time.
- A weakness to weigh: four digits and two short word lists is a small space for a key that unlocks the read key, slowed only by 100,000 rounds; and revoking removes the record but not a read key somebody has already taken from it.
