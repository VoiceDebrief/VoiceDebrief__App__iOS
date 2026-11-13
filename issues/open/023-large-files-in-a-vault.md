# 023: Files over 4 MB in a vault (presigned upload and download)

**Status:** open. Asked for by the owner, 13 November 2026: no recording may be left out of the vault because
it is long. The audio saved is the compressed `.m4a`; that is settled for now.

Today `VaultBook.largestAudio` is 3.8 MB (about a quarter of an hour at the app's bit rate) and a longer
note is saved to the vault without its audio. The audio is still on the device; it is the vault copy that is
missing.

## How sgit does it (read from `sgit_ai`, `network/api/Vault__API.py` and `core/actions/push/Vault__Batch.py`)

An encrypted blob over 4 MB (`LARGE_BLOB_THRESHOLD`) does not go in the batch. Instead:

1. `POST /api/vault/presigned/initiate/{vault_id}` with the write-key header and
   `{file_id, file_size_bytes, num_parts}` (`num_parts` 0 lets the server choose, 10 MB a part). The answer is
   `{upload_id, part_urls: [{part_number, upload_url}], part_size}`.
2. `PUT` each part of the ciphertext to its `upload_url`; keep the `ETag` of each answer.
3. `POST /api/vault/presigned/complete/{vault_id}` with `{file_id, upload_id, parts: [{part_number, etag}]}`.
   On failure, `POST /api/vault/presigned/cancel/{vault_id}` with `{upload_id, file_id}`.
4. The tree entry for the file carries `large: true`.

Reading: `GET /api/vault/presigned/read-url/{vault_id}/{file_id}` gives `{url, expires_in}`; the blob is
fetched from that URL, in ranges of 8 MB. A server without the route answers `presigned_not_available`, 400,
404 or 501, and sgit falls back to the ordinary read.

## To do

- `SGitVault`: the four calls, the `large` flag when writing a tree and when reading one, download by range,
  the fallback. Raise the reader's 16 MB limit for large blobs. Record it in `SOURCE.md`.
- `VaultBook.save`: no size limit on the audio; progress for a long upload; a failed upload can be retried and
  never touches the note on the device.
- `ios-vault.yml`: Swift writes a vault with a file over 4 MB and `sgit` reads it, and the reverse.
- The presigned URL's host must be reachable: check it is https, as sgit does.
