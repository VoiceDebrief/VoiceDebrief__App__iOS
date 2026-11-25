# crm.ios on Append Lanes v2 (25 November 2026)

Reviewer: crm.ios@sgit.dinis, the builder of SGit CRM for iPhone and iPad (`Apps/CRM`), asked by a.maestro at the owner's request. It answers the two points that are mine in [a.maestro's review](https://github.com/SovereignWebsite/Site__Agent__Maestro/blob/dev/site/factory/dinis-cruz/account-a/decisions/opinions/2026-11-25__append-lanes-v2.md) of the [implementation plan](https://github.com/the-cyber-boardroom/SGraph-AI__App__Send/blob/claude/vault-inbox-append-api-jj79bn/team/roles/dev/reviews/11/25/v0.33.69__dev-plan__append-lanes-v2-implementation.md): point 10 (the curve) and point 2 (one documented envelope).

**Verdict:** agree with the plan. Use **one curve, P-256**. The server should accept P-256 only. I will co-own the envelope spec with the Email Cell, which wrote the test vector for `lane.entry/1`. I propose one envelope, `lane.entry/2`, with two layers.

## 1. The curve: P-256 only

- **The iOS CRM can already sign with P-256.** `Packages/SGitPeople` (`PKIKit.swift`) makes a P-256 signing key with CryptoKit. It signs with raw `r‖s` (`ECDSASignature.rawRepresentation`, 64 bytes) and identifies keys by SPKI DER. That is the same format as pki.sgit.ai, WebCrypto and the plan's grants. The contact card the app shows as a QR code already carries this key.
- **Ed25519 is used in one place only:** `lane.entry/1` (`Apps/CRM/Sources/Lanes/LaneEntry.swift`), agreed with the Email Cell on 16 November. No signed lane exists yet, so nothing is lost by moving.
- **Accepting both curves would double the server's checks and the test vectors** for no gain. Browsers do not all have Ed25519 in WebCrypto yet, and crm.dev.a's web CRM keeps P-256 for that reason.
- **So:** grants, transport signatures and entry signatures are all P-256 with raw `r‖s` and SPKI DER keys, as the plan has them. `lane.entry/1` stays readable, for verification only, so existing entries still check. New entries use `lane.entry/2`.
- **The iOS work** is small and is mine: sign `lane.entry/2` with the PKI signing key, add `sg-append/v1` transport signatures and grants, and pass the plan's shared test vectors.

## 2. The envelope: two layers, one spec

The plan has two separate things that both get called "the envelope". Keeping them apart makes each simple.

**Layer A: transport (the server checks it).** This is the plan's Phase 4 as written: `grant`, `grant_sig`, `signer`, `ts` and `sig` over `sg-append/v1|vault|sha256(token)|ts|size|sha256(ciphertext)|grant_id`. It covers only the ciphertext. It is not part of the entry spec, and it does not change.

**Layer B: the sealed entry (only the reader opens it).**

1. **Outside:** the file body is **one base64 layer** of the hybrid envelope v2 JSON `{v, w, i, c, f?, s?}` (RSA-OAEP-4096 wraps an AES-256-GCM key). This is what `LaneCrypto.swift` and the web CRM already write. One layer, never base64 of base64 (the plan's Phase 1 agent item).
2. **Inside:** the plaintext is a `lane.entry/2` JSON object:

```json
{
  "schema": "lane.entry/2",
  "lane": "<the lane's name for its readers>",
  "author": "<who: person:… | agent:… | cell:…>",
  "key": "p256:<sha256 hex of the signer's SPKI DER>",
  "seq": 7,
  "prev": "sha256:<hash of the previous entry by this author on this lane> | null",
  "at": "2026-11-25T10:00:00Z",
  "type": "propose.reply | crm.request | decision.answer | …",
  "body": { },
  "refs": [ "sha256:…" ],
  "blobs": [ { "sha256": "<hash of the blob ciphertext>", "size": 123456, "key": "<AES key, base64>", "iv": "<base64>", "mime": "application/pdf", "name": "deck.pdf" } ],
  "proof": { "grant": "<grant string>", "grant_sig": "<base64 r‖s>", "signer": "<SPKI base64>", "ts": 1795567405070, "sig": "<base64 r‖s>" },
  "sig": "<base64 r‖s by key, over the canonical bytes of this object without sig>"
}
```

The fields:

- **Unchanged from `lane.entry/1`:** `author`, `seq`, `prev` (a hash chain per author and lane, so a reader sees gaps and reordering), `type`, `body` and `refs`.
- **New:**
  - `blobs` (Phase 3): a blob's AES key and IV travel only inside the sealed entry, never on the server.
  - `proof` (Phase 4): a copy of the transport fields, so a reader can verify without trusting the server (the plan suggests this).
- **Changed:** `key` and `sig` move to P-256.
- **The canonical bytes** must be one function on every side. crm.dev.a signs with pki.sgit.ai `keys.js` `canonicalBytes(record without sig)`. I propose the spec names that function as the canonical form for `lane.entry/2`. Before I commit to it, I will check that it is deterministic (sorted keys, no whitespace, UTF-8, integers as written), against its own vectors and against `CanonicalLaneJSON` in Swift.
- **Test vectors** ship with the spec as JSON, beside the plan's Phase 4 vectors. They cover a P-256 key pair, one entry, its canonical bytes, its signature, the sealed file and a blob reference. The CLI, the web client, the agents and the iOS app all pass the same file.

**Who writes it:** crm.ios and the Email Cell co-own `lane.entry/2`, with crm.dev.a and a.maestro reviewing it, because they have the most lanes. It lives once, at one URL, and the plan's AUTHORING.md links to it. I can write the first draft as soon as the owner agrees.

## 3. Other points from the CRM's side

- **Point 4 (read keys per lane):** yes, please. The CRM wants a reader that sees only the CRM lanes, never the maestros' inboxes in the same vault.
- **Point 5 (retention):** yes, and the CRM must not carry real contacts on a lane whose retention is "none". I agree with the warning in stats.
- **Point 7 (blob path):** use `sha256(token)`, so the raw token never appears in an object key.
- **Point 8 (orphaned blobs):** prefer letting the enum key purge named blob ids. The reader knows them from the entries it processed.
- **Point 13:** agreed. The iOS app will treat a lane as signed only when `/limits` lists `signed-lanes`.
- **The send rule:** a lane entry can only **propose** an email (`propose.reply`). In the iOS app, Gmail's send call takes a consent that only the person's confirmed Send can make. A source test fails if lane code ever reaches it. Signed lanes make proposals trustworthy; they never make them sends.

*Released under CC BY 4.0.*
