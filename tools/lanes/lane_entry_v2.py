#!/usr/bin/env python3
"""lane.entry/2: the reference implementation and the maker and checker of its test vectors.

The spec is website/lanes/entry-v2/index.md. This file is the second reading of it: every rule there is a function
here, and `check` runs every vector, positive and negative, against them.

  python3 tools/lanes/lane_entry_v2.py generate website/lanes/entry-v2/vectors.json
  python3 tools/lanes/lane_entry_v2.py check    website/lanes/entry-v2/vectors.json

Needs the `cryptography` package (sgit-ai brings it). Apache 2.0. The keys in the vectors are throwaway: they
protect nothing and were made for the vectors only.
"""
import base64
import hashlib
import json
import os
import re
import sys

from cryptography.exceptions import InvalidSignature, InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SCHEMA = 'lane.entry/2'
FIELDS = {'schema', 'lane', 'author', 'seq', 'prev', 'at', 'type', 'body', 'refs', 'blobs', 'proof'}
AT = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
HASH = re.compile(r'^sha256:[0-9a-f]{64}$')
KEYID = re.compile(r'^p256:[0-9a-f]{64}$')
INLINE_LIMIT = 65536


class Refused(Exception):
    """A reader's refusal, with the error code the spec names."""
    def __init__(self, code, why):
        super().__init__(f'{code}: {why}')
        self.code = code


# ---- encodings ----

def b64(data):
    return base64.b64encode(data).decode()


def unb64(text):
    return base64.b64decode(text, validate=True)


def b64u(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def unb64u(text):
    if not re.fullmatch(r'[A-Za-z0-9_-]*', text):
        raise ValueError('not base64url')
    return base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))


def canonical(value):
    """Canonical JSON, as lane.entry/1 has it and JavaScript's JSON.stringify writes it: keys sorted by UTF-16 code
    unit, no whitespace, only quote, backslash and control characters escaped, integers only."""
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        raise Refused('E_NUMBER', 'a number that is not an integer')
    if isinstance(value, str):
        out = ['"']
        for ch in value:
            o = ord(ch)
            if ch == '"':
                out.append('\\"')
            elif ch == '\\':
                out.append('\\\\')
            elif ch in '\b\f\n\r\t':
                out.append({'\b': '\\b', '\f': '\\f', '\n': '\\n', '\r': '\\r', '\t': '\\t'}[ch])
            elif o < 0x20:
                out.append('\\u%04x' % o)
            else:
                out.append(ch)
        out.append('"')
        return ''.join(out)
    if isinstance(value, list):
        return '[' + ','.join(canonical(v) for v in value) + ']'
    if isinstance(value, dict):
        keys = sorted(value, key=lambda k: k.encode('utf-16-be'))
        return '{' + ','.join(canonical(k) + ':' + canonical(value[k]) for k in keys) + '}'
    raise Refused('E_FIELD', f'a value of type {type(value).__name__}')


def sha256(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


# ---- keys ----

def spki(public_key):
    return public_key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def key_id(spki_der):
    return 'p256:' + hashlib.sha256(spki_der).hexdigest()


def p256_from_scalar(hex_scalar):
    return ec.derive_private_key(int(hex_scalar, 16), ec.SECP256R1())


# ---- the entry ----

def signed_bytes(entry):
    """What `proof.sig` covers: the canonical JSON of the entry without `proof`."""
    rest = {k: v for k, v in entry.items() if k != 'proof'}
    return canonical(rest).encode()


def entry_hash(entry):
    """What `prev` and `refs` name: sha256 of the canonical JSON of the whole entry, `proof` included."""
    return sha256(canonical(entry).encode())


def make_entry(lane, author_id, private_key, type_, body, previous=None, at='2026-11-25T16:00:00Z', refs=(), blobs=()):
    der = spki(private_key.public_key())
    entry = {
        'schema': SCHEMA, 'lane': lane,
        'author': {'id': author_id, 'key': key_id(der), 'spki': b64u(der)},
        'seq': (previous['seq'] + 1) if previous else 1,
        'prev': entry_hash(previous) if previous else None,
        'at': at, 'type': type_, 'body': body, 'refs': list(refs), 'blobs': list(blobs),
    }
    r, s = decode_dss_signature(private_key.sign(signed_bytes(entry), ec.ECDSA(hashes.SHA256())))
    entry['proof'] = {'alg': 'ES256', 'sig': b64u(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}
    return entry


def inline_blob(name, media, data):
    return {'name': name, 'media': media, 'size': len(data), 'sha256': sha256(data), 'data': b64(data)}


def check_entry(entry, expect_key=None):
    """Every rule a reader applies to one entry, in the order the spec lists them. Returns nothing or refuses."""
    if not isinstance(entry, dict):
        raise Refused('E_FIELD', 'not an object')
    canonical(entry)                                   # E_NUMBER for any float, anywhere
    if entry.get('schema') != SCHEMA:
        raise Refused('E_SCHEMA', f'schema is {entry.get("schema")!r}')
    if set(entry) != FIELDS:
        raise Refused('E_FIELD', f'fields {sorted(set(entry) ^ FIELDS)} missing or unknown')
    a = entry['author']
    if not (isinstance(entry['lane'], str) and entry['lane'] and isinstance(entry['type'], str) and entry['type']
            and isinstance(a, dict) and set(a) == {'id', 'key', 'spki'} and isinstance(a['id'], str) and a['id']
            and isinstance(entry['refs'], list) and isinstance(entry['blobs'], list)
            and isinstance(entry['proof'], dict) and set(entry['proof']) == {'alg', 'sig'}):
        raise Refused('E_FIELD', 'a field has the wrong shape')
    if not (isinstance(entry['seq'], int) and not isinstance(entry['seq'], bool) and entry['seq'] >= 1):
        raise Refused('E_FIELD', 'seq is not a whole number from 1')
    if entry['seq'] == 1 and entry['prev'] is not None or entry['seq'] > 1 and not (isinstance(entry['prev'], str) and HASH.match(entry['prev'])):
        raise Refused('E_CHAIN', 'prev does not suit seq')
    if not (isinstance(entry['at'], str) and AT.match(entry['at'])):
        raise Refused('E_FIELD', 'at is not YYYY-MM-DDTHH:MM:SSZ')
    if not all(isinstance(r, str) and HASH.match(r) for r in entry['refs']):
        raise Refused('E_FIELD', 'a ref is not sha256:<64 hex>')
    try:
        der = unb64u(a['spki'])
        public = serialization.load_der_public_key(der)
    except Exception:
        raise Refused('E_KEY', 'author.spki is not a public key')
    if not (isinstance(public, ec.EllipticCurvePublicKey) and public.curve.name == 'secp256r1'):
        raise Refused('E_KEY', 'author.spki is not P-256')
    if not KEYID.match(a['key']) or a['key'] != key_id(der):
        raise Refused('E_KEY', 'author.key is not the hash of author.spki')
    if expect_key and a['key'] != expect_key:
        raise Refused('E_KEY', 'signed by a key the reader does not expect')
    if entry['proof']['alg'] != 'ES256':
        raise Refused('E_SIG', f'alg is {entry["proof"]["alg"]!r}')
    try:
        sig = unb64u(entry['proof']['sig'])
    except Exception:
        raise Refused('E_SIG', 'sig is not base64url')
    if len(sig) != 64:
        raise Refused('E_SIG', f'sig is {len(sig)} bytes, not raw r||s (64)')
    try:
        public.verify(encode_dss_signature(int.from_bytes(sig[:32], 'big'), int.from_bytes(sig[32:], 'big')),
                      signed_bytes(entry), ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        raise Refused('E_SIG', 'the signature does not verify')
    for blob in entry['blobs']:
        if not (isinstance(blob, dict) and {'name', 'media', 'size', 'sha256'} <= set(blob) <= {'name', 'media', 'size', 'sha256', 'data', 'ref'}
                and ('data' in blob) != ('ref' in blob) and HASH.match(str(blob['sha256']))):
            raise Refused('E_BLOB', 'a blob has the wrong shape')
        if 'data' in blob:
            data = unb64(blob['data'])
            if len(data) != blob['size'] or sha256(data) != blob['sha256'] or len(data) > INLINE_LIMIT:
                raise Refused('E_BLOB', 'an inline blob does not match its size and hash, or is too big to inline')


def check_chain(entries):
    """Entries by one author on one lane, in order: seq 1, 2, 3 …, each prev the hash of the one before."""
    previous = None
    for entry in entries:
        check_entry(entry)
        if previous and (entry['author']['key'] != previous['author']['key'] or entry['lane'] != previous['lane']):
            raise Refused('E_CHAIN', 'a chain is one author on one lane')
        if entry['seq'] != (previous['seq'] + 1 if previous else 1) or entry['prev'] != (entry_hash(previous) if previous else None):
            raise Refused('E_CHAIN', f'seq {entry["seq"]} does not follow the entry before')
        previous = entry


# ---- the envelope and the wire ----

def seal(entry, recipient_public, aes_key=None, iv=None):
    """Hybrid envelope v2 around the canonical entry, then one base64 layer: the sg-append/v1 `payload`."""
    aes_key = aes_key or os.urandom(32)
    iv = iv or os.urandom(12)
    c = AESGCM(aes_key).encrypt(iv, canonical(entry).encode(), None)
    w = recipient_public.encrypt(aes_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    envelope = json.dumps({'v': 2, 'w': b64(w), 'i': b64(iv), 'c': b64(c)})
    return b64(envelope.encode())


def open_payload(payload, recipient_private):
    """A reader's first steps: one base64 layer, the envelope, the entry. Refuses anything else."""
    try:
        text = unb64(payload).decode()
    except Exception:
        raise Refused('E_PAYLOAD', 'payload is not base64 of text')
    try:
        envelope = json.loads(text)
    except Exception:
        raise Refused('E_PAYLOAD', 'payload is not one base64 layer over the envelope JSON (two layers is lane.entry/1)')
    if not (isinstance(envelope, dict) and envelope.get('v') == 2 and set(envelope) == {'v', 'w', 'i', 'c'}):
        raise Refused('E_ENVELOPE', 'not a hybrid envelope v2')
    try:
        key = recipient_private.decrypt(unb64(envelope['w']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
        plain = AESGCM(key).decrypt(unb64(envelope['i']), unb64(envelope['c']), None)
    except (ValueError, InvalidTag):
        raise Refused('E_ENVELOPE', 'the envelope does not open with this key')
    entry = json.loads(plain.decode())
    if canonical(entry).encode() != plain:
        raise Refused('E_CANONICAL', 'the sealed entry is not in canonical form')
    return entry


# ---- the vectors ----

def generate(path):
    author = p256_from_scalar('6a5f3d2c1b0e9f8a7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e')       # throwaway
    other = p256_from_scalar('1f2e3d4c5b6a79880f1e2d3c4b5a69788796a5b4c3d2e1f00112233445566778')        # throwaway
    rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)                             # throwaway
    lane = 'example-lane'

    e1 = make_entry(lane, 'person:example', author, 'note', {'text': 'Olá, first entry.\nTwo lines.'})
    e2 = make_entry(lane, 'person:example', author, 'propose.reply', {'client_ref': 'draft-1', 'text': 'Até quinta.'},
                    previous=e1, at='2026-11-25T16:01:00Z', refs=[entry_hash(e1)],
                    blobs=[inline_blob('note.txt', 'text/plain', b'an attachment, inline')])
    e3 = make_entry(lane, 'person:example', author, 'note', {'text': 'by reference'}, previous=e2, at='2026-11-25T16:02:00Z',
                    blobs=[{'name': 'photo.jpg', 'media': 'image/jpeg', 'size': 1048576, 'sha256': sha256(b'x' * 1048576), 'ref': 'blobs/photo.jpg'}])

    def changed(entry, **kw):
        d = json.loads(json.dumps(entry))
        for k, v in kw.items():
            d[k] = v
        return d

    def der_sig(entry):
        d = json.loads(json.dumps(entry))
        raw = unb64u(d['proof']['sig'])
        d['proof']['sig'] = b64u(encode_dss_signature(int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big')))
        return d

    forged_key = changed(e1, author={'id': 'person:example', 'key': key_id(spki(other.public_key())), 'spki': e1['author']['spki']})
    by_other = make_entry(lane, 'person:example', other, 'note', {'text': 'Olá, first entry.\nTwo lines.'})
    bad_blob = make_entry(lane, 'person:example', author, 'note', {'text': 'x'},
                          blobs=[dict(inline_blob('a.txt', 'text/plain', b'abc'), sha256=sha256(b'abd'))])
    payload1 = seal(e1, rsa_key.public_key())
    double = b64(payload1.encode())
    env = json.loads(unb64(payload1).decode())
    c = bytearray(unb64(env['c'])); c[0] ^= 1
    tampered_payload = b64(json.dumps(dict(env, c=b64(bytes(c)))).encode())

    vectors = {
        'about': 'Test vectors for lane.entry/2 (website/lanes/entry-v2/index.md), made by tools/lanes/lane_entry_v2.py. '
                 'Every key here is throwaway and protects nothing. A reader passes when it accepts every positive vector '
                 'and refuses every negative one with the code given.',
        'schema': SCHEMA,
        'keys': {
            'author_p256_private_scalar_hex': '6a5f3d2c1b0e9f8a7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e',
            'author_spki_b64url': e1['author']['spki'],
            'author_key_id': e1['author']['key'],
            'other_p256_private_scalar_hex': '1f2e3d4c5b6a79880f1e2d3c4b5a69788796a5b4c3d2e1f00112233445566778',
            'recipient_rsa_private_pkcs8_b64': b64(rsa_key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())),
            'recipient_rsa_public_spki_b64': b64(spki(rsa_key.public_key())),
        },
        'canonical': [
            {'value': {'b': 1, 'a': [True, None, 'é\n"\\'], 'é': {}, '\U0001F600': 0, 'ﬁ': 0},
             'text': canonical({'b': 1, 'a': [True, None, 'é\n"\\'], 'é': {}, '\U0001F600': 0, 'ﬁ': 0}),
             'why': 'keys sorted by UTF-16 code unit (the emoji, a surrogate pair, sorts before U+FB01); non-ASCII raw; only quote, backslash and controls escaped'},
        ],
        'positive': [
            {'name': 'first entry', 'entry': e1, 'signed_bytes_sha256': sha256(signed_bytes(e1)), 'hash': entry_hash(e1)},
            {'name': 'second entry: prev, a ref and an inline blob', 'entry': e2, 'hash': entry_hash(e2)},
            {'name': 'third entry: a blob by reference', 'entry': e3, 'hash': entry_hash(e3)},
            {'name': 'the chain of all three', 'chain': [e1, e2, e3]},
            {'name': 'the first entry on the wire', 'payload': payload1, 'opens_to_hash': entry_hash(e1)},
        ],
        'negative': [
            {'name': 'body changed after signing', 'entry': changed(e1, body={'text': 'changed'}), 'code': 'E_SIG'},
            {'name': 'signature in DER, not raw r||s', 'entry': der_sig(e1), 'code': 'E_SIG'},
            {'name': 'author.key is not the hash of author.spki', 'entry': forged_key, 'code': 'E_KEY'},
            {'name': 'a lane.entry/1 schema', 'entry': changed(e1, schema='lane.entry/1'), 'code': 'E_SCHEMA'},
            {'name': 'an unknown field', 'entry': changed(e1, extra=1), 'code': 'E_FIELD'},
            {'name': 'a float in the body', 'entry': changed(e1, body={'n': 1.5}), 'code': 'E_NUMBER'},
            {'name': 'at with milliseconds', 'entry': changed(e1, at='2026-11-25T16:00:00.000Z'), 'code': 'E_FIELD'},
            {'name': 'first entry with a prev', 'entry': changed(e1, prev=entry_hash(e2)), 'code': 'E_CHAIN'},
            {'name': 'an inline blob whose hash does not match', 'entry': bad_blob, 'code': 'E_BLOB'},
            {'name': 'a gap in the chain', 'chain': [e1, e3], 'code': 'E_CHAIN'},
            {'name': 'a chain that changes author key', 'chain': [by_other, e2], 'code': 'E_CHAIN'},
            {'name': 'two base64 layers (the lane.entry/1 wire)', 'payload': double, 'code': 'E_PAYLOAD'},
            {'name': 'ciphertext changed', 'payload': tampered_payload, 'code': 'E_ENVELOPE'},
        ],
    }
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(vectors, f, ensure_ascii=False, indent=1)
        f.write('\n')


def check(path):
    with open(path, encoding='utf-8') as f:
        v = json.load(f)
    rsa_private = serialization.load_der_private_key(unb64(v['keys']['recipient_rsa_private_pkcs8_b64']), None)
    author = p256_from_scalar(v['keys']['author_p256_private_scalar_hex'])
    assert key_id(spki(author.public_key())) == v['keys']['author_key_id']
    for c in v['canonical']:
        assert canonical(c['value']) == c['text'], c['why']
    passed = 0
    for p in v['positive']:
        if 'entry' in p:
            check_entry(p['entry'])
            assert entry_hash(p['entry']) == p['hash']
            if 'signed_bytes_sha256' in p:
                assert sha256(signed_bytes(p['entry'])) == p['signed_bytes_sha256']
        elif 'chain' in p:
            check_chain(p['chain'])
        else:
            assert entry_hash(open_payload(p['payload'], rsa_private)) == p['opens_to_hash']
        passed += 1
    for n in v['negative']:
        try:
            if 'entry' in n:
                check_entry(n['entry'])
            elif 'chain' in n:
                check_chain(n['chain'])
            else:
                check_entry(open_payload(n['payload'], rsa_private))
        except Refused as r:
            if r.code != n['code']:
                sys.exit(f'FAIL {n["name"]}: refused with {r.code}, expected {n["code"]}')
            passed += 1
            continue
        sys.exit(f'FAIL {n["name"]}: accepted, expected {n["code"]}')
    print(f'lane.entry/2 vectors: {passed} of {len(v["positive"]) + len(v["negative"])} as expected')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('generate', 'check'):
        sys.exit(__doc__)
    {'generate': generate, 'check': check}[sys.argv[1]](sys.argv[2])
