# lane.entry/2: the shared envelope for append lanes

One format for everything written to an append lane: a person's request to a site's keeper, a proposal from the CRM to the email cell, a decision answered from a phone, a file from the Drive and Chat tools. It replaces lane.entry/1 (Ed25519, 16 November 2026) and the per-application JSON that lanes carry today. Agreed by the owner on 25 November 2026 (item 20 of the Append Lanes v2 review). Co-owned by VoiceDebrief for iOS (a.ios) and the Email Cell. Final as of 25 November 2026; a change after this is lane.entry/3.

> Tested: [vectors.json](vectors.json) holds positive and negative vectors, made by the reference implementation [`tools/lanes/lane_entry_v2.py`](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/tools/lanes/lane_entry_v2.py), which passes all of them. An independent JavaScript reader using WebCrypto only, [`tools/lanes/check_vectors.mjs`](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/tools/lanes/check_vectors.mjs), agrees on canonical JSON, hashes, signatures and the wire. No application writes lane.entry/2 yet.

## The three layers

```
sg-append/v1     POST {endpoint}/api/vault/append/write/{vault_id}
                 {"append_token": "...", "payload": "<base64>"}
                        |
                 payload = base64( hybrid envelope v2 JSON )            one base64 layer, not two
                        |
hybrid env. v2   {"v": 2, "w": RSA-OAEP-SHA256(k), "i": iv, "c": AES-256-GCM_k(entry)}   each field base64
                        |
lane.entry/2     the entry: canonical JSON, signed by its author with P-256
```

### (A) Transport: sg-append/v1

The append lanes of the vault server (`dev.send.sgraph.ai` today): a POST of `{"append_token", "payload"}` to `/api/vault/append/write/{vault_id}`. The token can only append; only the lane's owner reads. A request must be under 6 MiB. The transport sees bytes it cannot read: who wrote an entry, and what it says, are inside the envelope. This is the append route as it runs today. In the Append Lanes v2 plan, sg-append/v1 is the Phase 4 signed lane, in which the server checks a grant and a signature at write time; that is not live yet. When Phase 4 ships, the request also carries the sg-append/v1 grant and signature, with the envelope and the entry unchanged, and the SGraph Send team's published text for that wire format wins over this page.

### (B) The envelope: hybrid envelope v2, one base64 layer

As sgit's `PKI__Crypto.hybrid_encrypt` writes it, and as `LaneCrypto` (this repository) and the Sovereign Websites' `send.js` already do: a fresh 256-bit AES key `k`; `c` is AES-256-GCM of the entry's bytes with a 12-byte `i`, the 16-byte tag appended; `w` is `k` wrapped with RSA-OAEP, SHA-256 for both the hash and MGF1, to the lane owner's RSA key (4096 bits for sgit keys). Fields `v`, `w`, `i`, `c`, each value standard base64 with padding.

**One base64 layer.** The `payload` is the base64 of the envelope's JSON text. lane.entry/1 and the lanes of today put a second base64 layer around that; lane.entry/2 does not, and a reader refuses a payload that decodes to base64 instead of to JSON (`E_PAYLOAD`), so the two can never be mistaken for each other.

The bytes inside `c` are the entry in canonical JSON, exactly; a reader refuses an entry that is not (`E_CANONICAL`).

### (C) The entry

```
{
  "schema": "lane.entry/2",
  "lane":   "<the lane: a vault id, or a name agreed by its readers>",
  "author": { "id": "<who, e.g. person:dinis or agent:a.ios>",
              "key": "p256:<hex SHA-256 of the SPKI DER>",
              "spki": "<base64url of the P-256 SubjectPublicKeyInfo DER>" },
  "seq":    1,
  "prev":   null,
  "at":     "2026-11-25T16:00:00Z",
  "type":   "<what it is: note, propose.reply, answer, message …>",
  "body":   { … any JSON the type defines … },
  "refs":   [ "sha256:<hex>", … ],
  "blobs":  [ { "name", "media", "size", "sha256", "data" | "ref" }, … ],
  "proof":  { "alg": "ES256", "sig": "<base64url of r||s, 64 bytes>" }
}
```

| Field | Rule |
|---|---|
| `schema` | Exactly `lane.entry/2`. |
| `lane` | A non-empty string. A chain is one author on one lane. |
| `author` | `id` names who wrote it, for people; `key` is what a reader trusts: `p256:` and the hex SHA-256 of `spki`'s DER bytes; `spki` carries the public key so a reader can verify without a lookup. Trust comes from the reader's own list of keys, never from the entry. |
| `seq`, `prev` | Per author and lane: `seq` 1, 2, 3 … with no gaps; `prev` is `null` for 1 and otherwise the hash of the author's entry before. A reader that sees a gap or a fork stops reading that chain (`E_CHAIN`). |
| `at` | UTC, `YYYY-MM-DDTHH:MM:SSZ`, no fractions. The author's clock: informative, not ordering. |
| `type` | A non-empty string, defined by the applications that share the lane. |
| `body` | Any JSON value. Integers only, anywhere in the entry: a float is refused (`E_NUMBER`). |
| `refs` | Hashes of other entries this one answers or builds on, each `sha256:<64 hex>`. |
| `blobs` | Files: `name`, `media` (a media type), `size` in bytes, `sha256` of the bytes, and either `data` (the bytes in standard base64, at most 64 KiB) or `ref` (where the bytes are kept, for example a path in the lane owner's vault). A reader checks `data` against `size` and `sha256` (`E_BLOB`); bytes fetched by `ref` are checked the same way. |
| `proof` | `alg` is `ES256`: ECDSA P-256 with SHA-256. `sig` is the raw 64 bytes r‖s (the IEEE P1363 form WebCrypto and CryptoKit produce), base64url without padding. DER is refused (`E_SIG`). |

**Canonical JSON**, as lane.entry/1 has it and JavaScript's `JSON.stringify` writes it once keys are sorted: object keys sorted by UTF-16 code unit, no whitespace, strings escaped only for quote, backslash and control characters (`\b \f \n \r \t`, others `\u00XX` in lower case), slash and non-ASCII left raw, integers only.

**What is signed:** the canonical JSON of the entry without `proof`. **The entry's hash** (for `prev` and `refs`): `sha256:` and the hex SHA-256 of the canonical JSON of the whole entry, `proof` included.

## A reader, in order

1. `E_PAYLOAD`: the payload is base64 of the envelope JSON, one layer.
2. `E_ENVELOPE`: `v` is 2 with exactly `v`, `w`, `i`, `c`, and it opens with the lane owner's key (the GCM tag checks).
3. `E_CANONICAL`: the opened bytes are canonical JSON.
4. `E_NUMBER`, `E_SCHEMA`, `E_FIELD`: no floats; the schema; exactly the eleven fields, each in its shape.
5. `E_KEY`: `spki` is a P-256 key and `key` is its hash; the key is one the reader trusts for this author.
6. `E_SIG`: `alg` is ES256, `sig` is 64 bytes and verifies over the signed bytes.
7. `E_BLOB`: each blob has its shape and each inline blob matches its size and hash.
8. `E_CHAIN`: with the author's earlier entries on the lane, `seq` and `prev` follow.

An entry refused at any step is not acted on. A reader may keep it, marked with the code, for whoever looks into it.

## From lane.entry/1

| | lane.entry/1 | lane.entry/2 |
|---|---|---|
| Signature | Ed25519 | P-256 ES256, raw r‖s: the key every sgit bundle, the Secure Enclave and WebCrypto in every browser already have |
| Author | `author` string and `key` id | `author.id`, `author.key`, and `author.spki` so a reader can verify without a lookup |
| Files | in `body`, per application | `blobs`, inline or by reference, each with its hash |
| Proof field | `sig` at the top | `proof: {alg, sig}`, so a later algorithm is a new `alg`, not a new schema |
| Wire | two base64 layers | one |

Canonical JSON, the hash chain and `refs` are unchanged.

## Test vectors

[vectors.json](vectors.json), with throwaway keys (they protect nothing): a P-256 author key as its private scalar, a second P-256 key, and an RSA 2048 recipient key as base64 PKCS#8 DER. It has a canonical-JSON case; five positive vectors (three entries, one with a ref and an inline blob, one with a blob by reference; their chain; the first entry on the wire); and thirteen negative ones, each with the code a reader must refuse it with (a changed body, a DER signature, a forged key id, a lane.entry/1 schema, an unknown field, a float, milliseconds in `at`, a first entry with a `prev`, a blob hash that does not match, a gap, a change of author key, two base64 layers, a changed ciphertext). ECDSA signatures are randomised, so the vectors are for checking, not for reproducing byte for byte.

```
python3 tools/lanes/lane_entry_v2.py check website/lanes/entry-v2/vectors.json
node tools/lanes/check_vectors.mjs website/lanes/entry-v2/vectors.json
```

## Who reads and writes it

- **VoiceDebrief for iOS**: owner-mode answers and messages, and requests to a Sovereign Website's keeper, move to lane.entry/2 once their receivers read it.
- **The Email Cell**: co-owner; adopted it as written on 25 November 2026 (its canonical JSON matches pki.sgit.ai's `keys.js` `canon()`). Its outbox becomes entry types `mail.outbox-draft/1`, `mail.outbox-approval/1` (author `person:dinis`, `refs` naming the draft entry) and `mail.outbox-sent/1`, with attachments in `blobs` by reference. For encrypted blobs it puts the plaintext's hash in `sha256`, `ref` as `append-blob:<ciphertext sha256>`, and the key and IV in the body: a reader checks the bytes after decrypting them, as the blob rule says.
- **The Drive and Chat tools** (a.drive): their lane reader is written against this page and its vectors.
