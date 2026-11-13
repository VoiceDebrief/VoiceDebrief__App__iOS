#!/usr/bin/env python3
"""The public half of what sgit_make.py or keysjs_make.mjs made: the form that is committed for the app's unit tests.

    public_fixture.py <made.json> <out.json>

Everything that is or needs a private key is left out (private keys, passphrases, sealed envelopes), and an
identity is reduced to its public bundle. What stays can be checked with public keys alone: bundles,
fingerprints, key codes, signatures, statements, canonical forms, the sign-in request, delegation and answer.
No private key is committed to this repository, not even a throwaway one: the checks that need one run in
pki-interop.yml, against keys made in the run.
"""
import json, sys

PRIVATE = {'passphrase', 'private_key.pem', 'signing_private.pem', 'to-self.enc', 'unsigned.enc', 'sealed.enc', 'sealed_text'}


def main():
    with open(sys.argv[1], encoding='utf-8') as f:
        made = json.load(f)
    out = {}
    for name, value in made.items():
        if name in PRIVATE:
            continue
        if name in ('identity', 'browser'):
            value = json.dumps({'bundle': json.loads(value)['bundle']})
        out[name] = value
    out['_about'] = made.get('_about', '') + ' Public half only (scripts/pki-interop/public_fixture.py): no private key, in any form.'
    text = json.dumps(out, indent=1, ensure_ascii=False) + '\n'
    if 'PRIVATE KEY' in text or '"private"' in text:
        sys.exit('refusing to write: private key material is still in it')
    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        f.write(text)


if __name__ == '__main__':
    main()
