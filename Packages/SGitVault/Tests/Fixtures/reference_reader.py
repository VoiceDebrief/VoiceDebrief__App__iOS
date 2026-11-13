#!/usr/bin/env python3
"""The read path SGitVault (Swift) implements, in 90 lines of Python, run
against the fixtures. It uses only HMAC, HKDF, AES-GCM, SHA-256, zlib and
ECDSA P-256, as the Swift code does, so the two can be compared step by step.

Usage: python3 -I reference_reader.py <fixtures-dir>     (exit 0 when every check passes)
"""
import base64, hashlib, hmac, json, sys, zlib
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

MAGIC = b'\x00sgz1'


class Reader:
    def __init__(self, root: Path, read_key: bytes, vault_id: str):
        self.root, self.rk, self.vid = root, read_key, vault_id
        self.sk = HKDF(hashes.SHA256(), 32, None, b'sg-vault-v1:structure-key').derive(read_key)

    def get(self, path):
        return (self.root / path).read_bytes()

    def file_id(self, domain):
        return hmac.new(self.rk, f'{domain}:{self.vid}'.encode(), hashlib.sha256).hexdigest()[:12]

    def decrypt(self, data):
        for key in (self.rk, self.sk):
            if data[:5] == MAGIC and len(data) > 17:
                try:
                    return zlib.decompress(AESGCM(key).decrypt(data[5:17], data[17:], None))
                except Exception:
                    pass
            try:
                return AESGCM(key).decrypt(data[:12], data[12:], None)
            except Exception:
                continue
        raise ValueError('decrypt failed')

    def obj(self, oid):
        data = self.get(f'bare/data/{oid}')
        width = len(oid) - len('obj-cas-imm-')
        assert width in (12, 32) and hashlib.sha256(data).hexdigest()[:width] == oid[-width:], f'id mismatch {oid}'
        return self.decrypt(data)

    def meta(self, b64):
        return self.decrypt(base64.b64decode(b64)).decode()

    def head(self, branch):
        index = json.loads(self.decrypt(self.get(f'bare/indexes/idx-pid-muw-{self.file_id("sg-vault-v1:file-id:branch-index")}')))
        assert 'packs' not in (index.get('features') or [])
        b = next(b for b in index['branches'] if b['name'] == branch and b['branch_type'] == 'named')
        return json.loads(self.decrypt(self.get(f'bare/refs/{b["head_ref_id"]}')))['commit_id']

    def verify_signature(self, commit):
        body = {k: v for k, v in commit.items() if k not in ('signature', 'user_signature')}
        data = json.dumps(body, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
        pem = json.loads(self.decrypt(self.get(f'bare/keys/{commit["author_key_id"]}')))['pem']
        sig = base64.b64decode(commit['signature'])
        key = serialization.load_pem_public_key(pem.encode())
        key.verify(utils.encode_dss_signature(int.from_bytes(sig[:32], 'big'), int.from_bytes(sig[32:], 'big')),
                   data, ec.ECDSA(hashes.SHA256()))

    def files(self, tree_id, prefix=''):
        for e in json.loads(self.obj(tree_id))['entries']:
            name = prefix + self.meta(e['name_enc'])
            if e.get('tree_id'):
                yield from self.files(e['tree_id'], name + '/')
            else:
                yield name, e

    def history(self, commit_id):
        out = []
        while commit_id:
            c = json.loads(self.obj(commit_id))
            self.verify_signature(c)
            out.append(self.meta(c['message_enc']))
            commit_id = (c['parents'] or [None])[0]
        return out


def check(fixture: Path):
    e = json.loads((fixture / 'expected.json').read_text())
    r = Reader(fixture / 'server', bytes.fromhex(e['read_key_hex']), e['vault_id'])
    for branch, want in e['branches'].items():
        head = r.head(branch)
        commit = json.loads(r.obj(head))
        assert r.history(head) == want['messages'], (branch, r.history(head))
        got = {}
        for path, entry in r.files(commit['tree_id']):
            data = r.obj(entry['blob_id'])
            assert int(r.meta(entry['size_enc'])) == len(data)
            assert r.meta(entry['content_hash_enc']) == hashlib.sha256(data).hexdigest()[:12]
            got[path] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        assert got == {p: {'size': v['size'], 'sha256': v['sha256']} for p, v in want['files'].items()}, branch
        print(f'{fixture.name}/{branch}: {len(got)} files, {len(want["messages"])} commits, signatures verified')


if __name__ == '__main__':
    root = Path(sys.argv[1])
    for name in ('plain', 'deflate'):
        check(root / name)
