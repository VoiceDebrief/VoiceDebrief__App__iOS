#!/usr/bin/env python3
"""Grant owner mode to one install of VoiceDebrief, with the owner's own sgit key.

The app (Owner, This device, Register) shows a request, `or1.<json>.<signature>`, signed by the device's key.
This script, run by the owner on his own machine:

  1. checks the request: the device key signed it, and the fingerprint is that key's;
  2. shows what it is about to grant (the device's name, its key, where the key is kept) and asks;
  3. writes owner.grant/v1 to a file and signs it with `sgit pki sign` (stock sgit, the owner's passphrase);
  4. prints `og1.<envelope>`: the grant, its .sig and the owner's public bundle (`sgit pki export`).

The owner pastes or scans the og1 text into the app. Nothing here is secret: the private key never leaves sgit's
key store, and the output holds only a signature and public keys. The app accepts the grant only if the
signing fingerprint is one it pins as the owner's (OwnerHandshake.pinnedOwners).

  python3 tools/owner/grant.py --fingerprint <your key's fingerprint, from `sgit pki list`> 'or1....'
  python3 tools/owner/grant.py --fingerprint sha256:... --yes --out grant-dir < request.txt

Needs sgit-ai (pip install sgit-ai==0.27.0), which brings the `cryptography` package. Apache 2.0.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

APP = 'ai.voicedebrief.app'


def b64url_decode(text):
    return base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))


def b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def fingerprint_of(public_key):
    """sgit's fingerprint: sha256: and the first 16 hex digits of SHA-256 over the SPKI DER."""
    der = public_key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return 'sha256:' + hashlib.sha256(der).hexdigest()[:16]


def read_request(text):
    m = re.search(r'or1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)', text)
    if not m:
        sys.exit('No registration request (or1....) in the input.')
    raw, sig = b64url_decode(m.group(1)), b64url_decode(m.group(2))
    request = json.loads(raw)
    if request.get('kind') != 'owner.request/v1' or request.get('app') != APP:
        sys.exit(f'Not a VoiceDebrief owner request: {request.get("kind")}, {request.get("app")}')
    key = serialization.load_pem_public_key(request['deviceKey'].encode())
    if not isinstance(key, ec.EllipticCurvePublicKey) or key.curve.name != 'secp256r1':
        sys.exit('The device key is not ECDSA P-256.')
    if fingerprint_of(key) != request['device']:
        sys.exit('The fingerprint in the request is not its key\'s.')
    if len(sig) != 64:
        sys.exit('The request\'s signature is not 64 bytes.')
    der = encode_dss_signature(int.from_bytes(sig[:32], 'big'), int.from_bytes(sig[32:], 'big'))
    try:
        key.verify(der, raw, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        sys.exit('The request is not signed by the device key it names: it was changed on the way.')
    return request, raw


def sgit(*args, cwd):
    done = subprocess.run(['sgit', 'pki', *args], cwd=cwd, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f'sgit pki {" ".join(args)} failed:\n{done.stdout}\n{done.stderr}')
    return done.stdout


def main():
    p = argparse.ArgumentParser(description='Grant owner mode to one install of VoiceDebrief.')
    p.add_argument('request', nargs='?', help='the or1. text; read from standard input when left out')
    p.add_argument('--fingerprint', required=True, help='your sgit key, as `sgit pki list` shows it')
    p.add_argument('--note', help='a few words kept in the grant, e.g. "Dinis\'s iPad"')
    p.add_argument('--yes', action='store_true', help='do not ask before signing')
    p.add_argument('--out', help='a folder to keep grant.json and grant.json.sig in (default: a temporary one)')
    a = p.parse_args()

    request, raw = read_request(a.request if a.request else sys.stdin.read())
    print(f'Device:  {request["label"]}\nKey:     {request["device"]} ({request["kept"]})\nAsked:   {request["at"]}', file=sys.stderr)
    if not a.yes:
        print('Grant owner mode to this device with your key? [y/N] ', end='', file=sys.stderr, flush=True)
        if sys.stdin.isatty() and input().strip().lower() not in ('y', 'yes'):
            sys.exit('Not granted.')
        if not sys.stdin.isatty():
            sys.exit('Standard input is not a terminal: pass --yes to grant without asking.')

    folder = a.out or tempfile.mkdtemp(prefix='owner-grant-')
    os.makedirs(folder, exist_ok=True)
    bundle_text = sgit('export', a.fingerprint, cwd=folder)
    bundle = json.loads(bundle_text)
    grant = {
        'kind': 'owner.grant/v1',
        'app': APP,
        'device': request['device'],
        'request': 'sha256:' + hashlib.sha256(raw).hexdigest(),
        'owner': bundle['signing_fingerprint'],
        'granted': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    }
    if a.note:
        grant['note'] = a.note
    grant_bytes = json.dumps(grant, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
    path = os.path.join(folder, 'grant.json')
    with open(path, 'wb') as f:
        f.write(grant_bytes)
    sgit('sign', 'grant.json', '--fingerprint', a.fingerprint, cwd=folder)
    with open(path + '.sig', encoding='utf-8') as f:
        sig = f.read()
    envelope = {'grant': base64.b64encode(grant_bytes).decode(), 'sig': sig, 'owner': bundle}
    print(f'Signed by {bundle["signing_fingerprint"]}. Kept in {folder}. Paste this into the app:', file=sys.stderr)
    print('og1.' + b64url(json.dumps(envelope, sort_keys=True, separators=(',', ':')).encode()))


if __name__ == '__main__':
    main()
