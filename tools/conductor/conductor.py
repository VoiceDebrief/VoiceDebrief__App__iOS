#!/usr/bin/env python3
"""A conductor's inbox for VoiceDebrief notes: the receiving end of an sgit append lane.

A conductor is whoever receives notes: an agent session, or a person at a computer. It makes a key
pair and a lane, hands out a link (as text or as a QR code), and later opens what was sent to it.

    conductor.py setup "Name shown in the app"   make the key pair, the vault and the lane
    conductor.py link                            print the lane link to give to a sender
    conductor.py qr [file.png|file.svg]          the same link as a QR code (default inbox-qr.png)
    conductor.py selftest                        write one message to the lane and read it back
    conductor.py drain [folder]                  fetch, decrypt and file what has arrived

State lives in --home (default ~/.voicedebrief-conductor): the private key, the lane's tokens and
the vault. NEVER put that folder in a repository and never print its contents. The link and the QR
code are safe to give out: they hold a vault id, a token that can only write, and a public key.

Needs: pip install sgit-ai cryptography requests segno. The server asks for an access token to
create a vault: pass --token, or set SGIT_TOKEN; in a Claude cloud session, ask the owner for it with
the request_credential tool for the host (header x-sgraph-access-token) and pass --token proxy-injected.
"""
import argparse, base64, hashlib, json, os, secrets, subprocess, sys, urllib.parse

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

BASE = os.environ.get('SGIT_BASE_URL', 'https://dev.send.sgraph.ai')
OAEP = padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None)


class Inbox:
    def __init__(self, home):
        self.home = home
        self.state = json.load(open(os.path.join(home, 'lane.json')))
        self.spki = open(os.path.join(home, 'public.spki'), 'rb').read()
        self.vault_key = open(os.path.join(home, 'inbox/.sg_vault/local/vault_key')).read().strip()
        self.vault_id = self.vault_key.rsplit(':', 1)[1]

    def post(self, path, body, headers=None):
        return requests.post(f'{BASE}/api/vault/append/{path}/{self.vault_id}', json=body, headers=headers or {}, timeout=120)

    def link(self):
        key = base64.urlsafe_b64encode(self.spki).decode().rstrip('=')
        name = urllib.parse.quote(self.state.get('name', ''), safe='')
        return f"sgi1.{self.vault_id}.{self.state['append_token']}.{key}" + (f'#{name}' if name else '')

    def fingerprint(self):
        return 'sha256:' + hashlib.sha256(self.spki).hexdigest()[:16]

    def seal(self, plaintext):
        key, iv = AESGCM.generate_key(256), os.urandom(12)
        wrapped = serialization.load_der_public_key(self.spki).encrypt(key, OAEP)
        b64 = lambda b: base64.b64encode(b).decode()
        envelope = json.dumps({'v': 2, 'w': b64(wrapped), 'i': b64(iv), 'c': b64(AESGCM(key).encrypt(iv, plaintext, None))})
        return base64.b64encode(base64.b64encode(envelope.encode())).decode()

    def unseal(self, content):
        private = serialization.load_pem_private_key(open(os.path.join(self.home, 'private.pem'), 'rb').read(), None)
        envelope = json.loads(base64.b64decode(base64.b64decode(content)))
        key = private.decrypt(base64.b64decode(envelope['w']), OAEP)
        return AESGCM(key).decrypt(base64.b64decode(envelope['i']), base64.b64decode(envelope['c']), None)

    def enum(self):
        return {'x-sgraph-vault-enum-key': self.state['enum_key']}

    def pending(self):
        return self.post('list', {'include_content': False}, self.enum()).json().get('entries', [])


def setup(home, name, token):
    if os.path.exists(os.path.join(home, 'private.pem')):
        sys.exit(f'{home} already holds an inbox. Use another --home, or delete it to start again.')
    os.makedirs(home, mode=0o700, exist_ok=True)
    private = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    pem = private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    fd = os.open(os.path.join(home, 'private.pem'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(fd, pem); os.close(fd)
    open(os.path.join(home, 'public.spki'), 'wb').write(
        private.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo))
    state = {'name': name, 'append_token': secrets.token_hex(24), 'enum_key': secrets.token_hex(32)}
    fd = os.open(os.path.join(home, 'lane.json'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(fd, json.dumps(state).encode()); os.close(fd)

    sgit = ['sgit', '--base-url', BASE, '--token', token]
    quiet = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)        # sgit prints the vault key
    subprocess.run(sgit + ['create', 'inbox'], cwd=home, check=True, **quiet)
    vault = os.path.join(home, 'inbox')
    open(os.path.join(vault, 'README.md'), 'w').write('An inbox for VoiceDebrief notes. The notes are in its append lane.\n')
    subprocess.run(['sgit', 'commit', '-m', 'An inbox'], cwd=vault, check=True, **quiet)
    subprocess.run(sgit + ['push'], cwd=vault, check=True, **quiet)

    from sgit_ai.crypto.Vault__Crypto import Vault__Crypto
    inbox = Inbox(home)
    write_key = Vault__Crypto().derive_keys_from_vault_key(inbox.vault_key)['write_key']
    answer = inbox.post('configure', {'append_anchors': [hashlib.sha256(state['append_token'].encode()).hexdigest()],
                                      'enum_key_hash': hashlib.sha256(state['enum_key'].encode()).hexdigest()},
                        {'x-sgraph-vault-write-key': write_key, 'x-sgraph-access-token': token})
    if answer.status_code != 200:
        sys.exit(f'The server refused to configure the lane (status {answer.status_code}).')
    print(f'Inbox ready. Key {inbox.fingerprint()}. Give out the link (conductor.py link) or the QR code (conductor.py qr).')


def selftest(inbox):
    wrote = inbox.post('write', {'append_token': inbox.state['append_token'], 'payload': inbox.seal(b'{"kind":"selftest"}\nhello')})
    print('write:', wrote.status_code, '| pending now:', len(inbox.pending()))


def drain(inbox, out):
    os.makedirs(out, exist_ok=True)
    entries = inbox.pending()
    print(f'{len(entries)} pending message(s)')
    notes, done = {}, []
    for entry in entries:
        answer = inbox.post('fetch', {'inbox': entry['inbox'], 'file_ids': [entry['file_id']]}, inbox.enum())
        if answer.status_code != 200:
            print('could not fetch one message:', answer.status_code); continue
        files = answer.json().get('files') or answer.json().get('entries') or []
        if isinstance(files, dict):
            files = [{'file_id': k, **(v if isinstance(v, dict) else {'content': v})} for k, v in files.items()]
        for item in files:
            try:
                plain = inbox.unseal(item.get('content') or item.get('payload') or item.get('data'))
            except Exception as error:
                print('could not open one message:', type(error).__name__); continue
            head, _, body = plain.partition(b'\n')
            try: header = json.loads(head)
            except Exception: header = {'kind': 'unknown'}
            kind = header.get('kind', '')
            if kind == 'selftest':
                print('the self-test message opened'); done.append(entry); continue
            note = notes.setdefault(os.path.basename(str(header.get('note', 'unknown'))), {'audio': {}, 'header': None, 'files': {}})
            if kind == 'voicedebrief/audio/v1':
                note['audio'][header['part']] = body; note['header'] = header
            elif kind.startswith('voicedebrief/'):
                # run, clean, usage, and any later kind: filed under the note (or report) id by its name
                note['files'][os.path.basename(header.get('name') or kind.split('/')[1] + '.json')] = body
            done.append(entry)
    for note_id, note in notes.items():
        folder = os.path.join(out, note_id); os.makedirs(folder, exist_ok=True)
        header = note['header']
        if header:
            have = sorted(note['audio'])
            data = b''.join(note['audio'][p] for p in have)
            whole = len(have) == header['of'] and hashlib.sha256(data).hexdigest() == header['sha256']
            name = os.path.basename(header['name']) or 'audio.bin'
            open(os.path.join(folder, name), 'wb').write(data)
            print(f"note {note_id}: {name}, {len(data)} bytes, {'intact' if whole else 'INCOMPLETE OR CORRUPT'}, from {header.get('app')}")
        for name, body in note['files'].items():
            open(os.path.join(folder, name), 'wb').write(body)
            print(f'note {note_id}: {name}, {len(body)} bytes')
    by_lane = {}
    for entry in done: by_lane.setdefault(entry['inbox'], []).append(entry['file_id'])
    for lane, ids in by_lane.items():
        inbox.post('mark-processed', {'inbox': lane, 'file_ids': ids}, inbox.enum())


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--home', default=os.path.expanduser('~/.voicedebrief-conductor'))
    parser.add_argument('--token', default=os.environ.get('SGIT_TOKEN', ''))
    parser.add_argument('command', choices=['setup', 'link', 'qr', 'selftest', 'drain'])
    parser.add_argument('argument', nargs='?')
    args = parser.parse_args()
    if args.command == 'setup':
        if not args.token: sys.exit('Creating a vault needs the server access token: --token or SGIT_TOKEN.')
        return setup(args.home, args.argument or 'Conductor', args.token)
    inbox = Inbox(args.home)
    if args.command == 'link':
        print(inbox.link())
    elif args.command == 'qr':
        import segno
        out = args.argument or 'inbox-qr.png'
        segno.make(inbox.link(), error='l').save(out, scale=6, border=4)
        print(f'{out}: the lane of "{inbox.state.get("name", "")}", key {inbox.fingerprint()}')
    elif args.command == 'selftest':
        selftest(inbox)
    elif args.command == 'drain':
        drain(inbox, args.argument or os.path.join(args.home, 'received'))


if __name__ == '__main__':
    main()
