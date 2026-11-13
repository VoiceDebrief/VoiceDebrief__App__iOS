#!/usr/bin/env python3
"""sgit writes a vault that holds files over 4 MB, for Swift to read (the reverse of
sgit_reads_swift.py). CI runs this on Linux and hands the folder to the macOS job, which sets
SGITVAULT_SGIT_WROTE and runs LargeFileTests.

It drives sgit-ai's own Vault__Sync against its in-memory server, as generate_fixtures.py does.
That server has no presigned route, so sgit sends the large blob in a batch; the tree entry still
carries large: true, which is what the Swift reader must follow.

Usage:  python3 -I sgit_writes_large.py <output-dir>      (pip install sgit-ai==0.27.0)
Writes: <output-dir>/large/server/bare/...  and  <output-dir>/large/expected.json
The key is a THROWAWAY made for this test. The vault exists on no server.
"""
import hashlib, json, os, sys, tempfile
from pathlib import Path
from sgit_ai.core.Vault__Sync import Vault__Sync
from sgit_ai.crypto.Vault__Crypto import Vault__Crypto
from sgit_ai.network.api.Vault__API__In_Memory import Vault__API__In_Memory

VAULT_KEY = 'throwaway-fixture-large:fixtlarge1'


def main():
    out = Path(sys.argv[1]) / 'large'
    out.mkdir(parents=True, exist_ok=True)
    vault_id = VAULT_KEY.rsplit(':', 1)[1]
    api = Vault__API__In_Memory().setup()
    crypto = Vault__Crypto()
    sync = Vault__Sync(crypto=crypto, api=api)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / 'work'
        sync.init(str(work), vault_key=VAULT_KEY)
        (work / 'media').mkdir()
        (work / 'README.md').write_text('# Large files, written by sgit\n')
        (work / 'media' / 'random-5mb.bin').write_bytes(os.urandom(5 * 1024 * 1024 + 123))
        (work / 'media' / 'random-9mb.bin').write_bytes(os.urandom(9 * 1024 * 1024 + 7))
        (work / 'media' / 'small.bin').write_bytes(os.urandom(70_000))
        sync.commit(str(work), message='sgit commits two large files')
        sync.push(str(work))
        files = {}
        for p in sorted(work.rglob('*')):
            if p.is_file() and '.sg_vault' not in p.parts:
                data = p.read_bytes()
                files[p.relative_to(work).as_posix()] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        keys = crypto.derive_keys_from_vault_key(VAULT_KEY)
    n = 0
    for key, data in sorted(api._store.items()):
        if key.startswith(vault_id + '/'):
            dest = out / 'server' / key[len(vault_id) + 1:]
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            n += 1
    (out / 'expected.json').write_text(json.dumps({
        'WARNING': 'THROWAWAY test key for this test only. This vault exists on no server.',
        'vault_id': vault_id, 'vault_key': f'sgit_private_vault_{VAULT_KEY}',
        'read_key_hex': keys['read_key'], 'write_key_hex': keys['write_key'],
        'messages': ['sgit commits two large files', 'init'], 'files': files,
    }, indent=1) + '\n')
    print(f'sgit wrote {vault_id}: {len(files)} files, {n} server files')


if __name__ == '__main__':
    main()
