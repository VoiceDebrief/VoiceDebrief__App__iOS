#!/usr/bin/env python3
"""What `sgit pki` makes, for Swift to read: a key store, an exported bundle, a detached signature, two envelopes.

    sgit_make.py <home folder to make the key in> <out.json>

Runs the installed `sgit` (sgit-ai) with HOME set to the given folder, so nothing touches a real key store.
The key is made for this file, its passphrase is written beside it, and it protects nothing.
"""
import json, os, subprocess, sys

PASSPHRASE = 'throwaway passphrase, protects nothing'
MESSAGE = 'signed and sealed by sgit: “quotes”, é, 日本, 😀\n'


def main():
    home, out = sys.argv[1], sys.argv[2]
    os.makedirs(home, exist_ok=True)
    env = dict(os.environ, HOME=home, SG_SEND_PASSPHRASE=PASSPHRASE)

    def sgit(*args):
        done = subprocess.run(['sgit', 'pki', *args], env=env, cwd=home, capture_output=True, text=True)
        if done.returncode != 0:
            sys.exit(f'sgit pki {" ".join(args)} failed:\n{done.stdout}\n{done.stderr}')
        return done.stdout

    sgit('keygen', '--label', 'sgit interop (throwaway)')
    fingerprint = sgit('list').split()[0]
    bundle = sgit('export', fingerprint)
    with open(os.path.join(home, 'message.txt'), 'w', encoding='utf-8') as f:
        f.write(MESSAGE)
    sgit('sign', 'message.txt', '--fingerprint', fingerprint)
    sgit('encrypt', 'message.txt', '--recipient', fingerprint, '--fingerprint', fingerprint, '--output', 'to-self.enc')
    sgit('encrypt', 'message.txt', '--recipient', fingerprint, '--output', 'unsigned.enc')

    def read(*parts):
        with open(os.path.join(home, *parts), encoding='utf-8') as f:
            return f.read()

    store = ('.sg-send', 'keys', fingerprint.replace(':', '_'))
    version = subprocess.run(['sgit', '--version'], env=env, capture_output=True, text=True).stdout.strip()
    made = {
        '_about': f'Made by {version or "sgit"} through scripts/pki-interop/sgit_make.py. A throwaway key: it protects nothing.',
        'passphrase': PASSPHRASE, 'fingerprint': fingerprint, 'bundle': bundle,
        'message': MESSAGE, 'message.sig': read('message.txt.sig'), 'to-self.enc': read('to-self.enc'), 'unsigned.enc': read('unsigned.enc'),
    }
    for name in ('metadata.json', 'private_key.pem', 'public_key.pem', 'signing_private.pem', 'signing_public.pem'):
        made[name] = read(*store, name)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(made, f, indent=1, ensure_ascii=False)
        f.write('\n')
    print(f'sgit made {out}: {fingerprint} (encryption), {json.loads(bundle)["signing_fingerprint"]} (signing)')


if __name__ == '__main__':
    main()
