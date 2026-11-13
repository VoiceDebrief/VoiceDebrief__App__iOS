#!/usr/bin/env python3
"""sgit reads what Swift wrote. CI runs this on Linux on the vaults the macOS
`swift test` exported (SGITVAULT_ROUNDTRIP_OUT): each <dir>/<fixture>/server is
loaded into sgit-ai's in-memory server, sgit clones the vault, switches to the
branch Swift pushed, checks every commit signature, and compares the files.

Usage: python3 -I sgit_reads_swift.py <export-dir>      (pip install sgit-ai==0.27.0)
Keys in the export are the fixtures' THROWAWAY test keys.
"""
import hashlib, json, os, sys, tempfile
from pathlib import Path
from sgit_ai.core.Vault__Sync import Vault__Sync
from sgit_ai.crypto.Vault__Crypto import Vault__Crypto
from sgit_ai.network.api.Vault__API__In_Memory import Vault__API__In_Memory


def check(export: Path) -> None:
    want = json.loads((export / 'expected.json').read_text())
    api = Vault__API__In_Memory().setup()
    server = export / 'server'
    for f in server.rglob('*'):
        if f.is_file():
            api._store[f"{want['vault_id']}/{f.relative_to(server).as_posix()}"] = f.read_bytes()
    sync = Vault__Sync(crypto=Vault__Crypto(), api=api)
    with tempfile.TemporaryDirectory() as tmp:
        work = str(Path(tmp) / 'clone')
        sync.clone(want['vault_key'], work)
        if want['branch'] != 'current':                 # a clone is already on current
            sync.switch_branch(work, want['branch'])
        got = {}
        for p in sorted(Path(work).rglob('*')):
            if p.is_file() and '.sg_vault' not in p.parts:
                data = p.read_bytes()
                got[p.relative_to(work).as_posix()] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        assert got == want['files'], f'files differ:\n sgit  {sorted(got)}\n swift {sorted(want["files"])}'
        counts = sync.verify_signatures(work)['counts']
        print(f"{export.name}: sgit cloned {want['vault_id']}, branch {want['branch']}: {len(got)} files match; "
              f"signatures {counts}")
        assert counts['verified'] >= len(want['messages']) and not any(
            counts[k] for k in ('bad', 'unsigned', 'no-key', 'missing')), f'signature problems: {counts}'


if __name__ == '__main__':
    root = Path(sys.argv[1])
    exports = [d for d in sorted(root.iterdir()) if (d / 'expected.json').exists()]
    assert exports, f'nothing exported under {root}'
    for d in exports:
        check(d)
