#!/usr/bin/env python3
"""Test vectors for the passkey door derivation (SGitVault VaultDoor).

A port, by reading, of https://promptugal.news/assets/vault/door.js (fetched 7 Nov 2026):
    prf input   = SHA-256("web-summit.newsroom.sgit.ai/door/v1")
    seed        = HKDF-SHA256(ikm = PRF bytes, salt = SHA-256("web-summit.newsroom.sgit.ai"), info "sgit/door/v1", 32)
    passphrase  = hex(HKDF-SHA256(seed, salt = empty, info "sgit/door/v1/passphrase", 32))
    vault id    = 8 of [a-z0-9] from HKDF-SHA256(seed, empty, "sgit/door/v1/id[/counter][/round]", 64), bytes < 252
    read key    = sgit PBKDF2 of passphrase and vault id
The inputs below are made-up bytes, not anyone's passkey output.
Usage: python3 -I door_vectors.py > vectors.json
"""
import hashlib, json, sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

RP = 'web-summit.newsroom.sgit.ai'
ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789'
B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'


def hkdf(ikm, salt, info, n):
    return HKDF(hashes.SHA256(), n, salt if salt else None, info.encode()).derive(ikm)


def vault_id(seed, counter=0):
    out = ''
    for rnd in range(8):
        if len(out) >= 8:
            break
        info = 'sgit/door/v1/id' + (f'/{counter}' if counter else '') + (f'/{rnd}' if rnd else '')
        for b in hkdf(seed, b'', info, 64):
            if b < 252:
                out += ALPHABET[b % 36]
            if len(out) == 8:
                break
    return out


def recovery_bytes(code):
    s = ''.join(c for c in code.upper() if c in B32)
    bits = ''.join(format(B32.index(c), '05b') for c in s)
    return bytes(int(bits[i * 8:i * 8 + 8], 2) for i in range(16))


def door(ikm):
    seed = hkdf(ikm, hashlib.sha256(RP.encode()).digest(), 'sgit/door/v1', 32)
    passphrase = hkdf(seed, b'', 'sgit/door/v1/passphrase', 32).hex()
    vid = vault_id(seed)
    read = PBKDF2HMAC(hashes.SHA256(), 32, f'sg-vault-v1:{vid}'.encode(), 600_000).derive(passphrase.encode())
    return dict(ikm_hex=ikm.hex(), seed_hex=seed.hex(), passphrase=passphrase, vault_id=vid, read_key_hex=read.hex())


if __name__ == '__main__':
    code = 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ'
    out = dict(source='https://promptugal.news/assets/vault/door.js', rp_for_derivation=RP,
               prf_input_text=f'{RP}/door/v1', prf_input_sha256=hashlib.sha256(f'{RP}/door/v1'.encode()).hexdigest(),
               recovery_code=code, recovery_bytes_hex=recovery_bytes(code).hex(),
               vectors=[door(bytes([1] * 32)), door(bytes(range(32))), door(recovery_bytes(code))])
    json.dump(out, sys.stdout, indent=1)
    print()
