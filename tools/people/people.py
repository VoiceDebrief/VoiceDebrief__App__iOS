#!/usr/bin/env python3
"""The people layer, in Python: a reference for SGitPeople's formats, and a way for an agent to be a contact.

Cards, sealed and signed messages and inboxes exactly as Packages/SGitPeople writes and reads them:

    people.py --home H setup "Name" [--inbox]   make a key pair (and an inbox, which needs the access key)
    people.py --home H card                     print this person's card (sgc1.…)
    people.py --home H add CARD                 add a contact from a card's text
    people.py --home H invite CARD              seal the access key to a newcomer's card: prints sgm1.…
    people.py --home H accept SGM               open an invitation, keep the access key, make an inbox,
                                                send the full card to the inviter
    people.py --home H send FINGERPRINT TEXT    a text message to a contact's inbox
    people.py --home H reply CARD ID TEXT       answer a message or a note (by its id) in the card's inbox,
                                                with this person's card inside, so the app can check who wrote
    people.py --home H check                    fetch, open, keep and mark processed what has arrived
    people.py --home H destroy                  delete this person's inbox vault from the server

State lives in --home: private keys, the inbox's enumeration key and vault key, the access key. NEVER put
that folder in a repository and never print its contents. A card and an `sgm1.` text are safe to hand over.

The access key: pass --access-key, or set SGIT_TOKEN. In a Claude cloud session the proxy adds the real one to
every request to dev.send.sgraph.ai: pass --access-key proxy-injected, and that placeholder is what an
invitation then carries.

Needs: pip install sgit-ai cryptography requests.
"""
import argparse, base64, hashlib, json, os, secrets, subprocess, sys, time

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SERVER = os.environ.get('SGIT_BASE_URL', 'https://dev.send.sgraph.ai')
OAEP = padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None)
REGISTRY, CARD_KIND, MESSAGE_FORMAT = 'sgit.ai/people', 'sgit.ai/people/card/v1', 'sgit.ai/people/message/v1'


# --- encodings, as PKIKit writes them ---------------------------------------------------------------------

def b64(b): return base64.b64encode(b).decode()
def b64url(b): return base64.urlsafe_b64encode(b).decode().rstrip('=')
def unb64url(s): return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))
def canonical(value): return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
def fingerprint(spki): return 'sha256:' + hashlib.sha256(spki).hexdigest()[:16]
def pem(spki): return serialization.load_der_public_key(spki).public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
def spki_of(pem_text): return serialization.load_pem_public_key(pem_text.encode()).public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
def now(): return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def bundle(encrypt_spki, sign_spki, label):
    return {'v': 1, 'encrypt': pem(encrypt_spki), 'sign': pem(sign_spki), 'label': label,
            'fingerprint': fingerprint(encrypt_spki), 'signing_fingerprint': fingerprint(sign_spki)}


def sign_raw(private, data):
    r, s = decode_dss_signature(private.sign(data, ec.ECDSA(hashes.SHA256())))
    return r.to_bytes(32, 'big') + s.to_bytes(32, 'big')


def verify_raw(sign_spki, signature, data):
    try:
        key = serialization.load_der_public_key(sign_spki)
        key.verify(encode_dss_signature(int.from_bytes(signature[:32], 'big'), int.from_bytes(signature[32:], 'big')),
                   data, ec.ECDSA(hashes.SHA256()))
        return True
    except Exception:
        return False


# --- the card ----------------------------------------------------------------------------------------------

def card_statement(name, b, inbox, created_at):
    body = {'kind': CARD_KIND, 'name': name, 'bundle': b}
    if inbox: body['inbox'] = inbox
    return {'v': 1, 'type': 'card', 'registry': REGISTRY, 'record': b['signing_fingerprint'],
            'signer': b['signing_fingerprint'], 'created_at': created_at, 'body': body}


def make_card(me, inbox):
    b = me['bundle']
    created_at = now()
    sig = sign_raw(me['sign_private'], (canonical(card_statement(me['name'], b, inbox, created_at)) + '\n').encode())
    details = {'name': me['name'], 'label': b['label'], 'created_at': created_at}
    if inbox: details['inbox'] = inbox
    return 'sgc1.' + '.'.join([b64url(me['encrypt_spki']), b64url(me['sign_spki']), b64url(canonical(details).encode()), b64url(sig)])


def read_card(text):
    """The card in text, checked: the bundle is rebuilt from its two keys and the signature must be theirs."""
    start = text.index('sgc1.') + 5
    code = ''
    for c in text[start:]:
        if not (c.isalnum() or c in '-_.'): break
        code += c
    parts = code.split('.')[:4]
    code = '.'.join(parts)
    enc, sig_key, details_b, sig = parts
    encrypt_spki, sign_spki, details, signature = unb64url(enc), unb64url(sig_key), json.loads(unb64url(details_b)), unb64url(sig)
    b = bundle(encrypt_spki, sign_spki, details.get('label', ''))
    statement = card_statement(details['name'], b, details.get('inbox'), details['created_at'])
    if not verify_raw(sign_spki, signature, (canonical(statement) + '\n').encode()):
        raise ValueError('the card does not check')
    return {'name': details['name'], 'bundle': b, 'inbox': details.get('inbox'), 'created_at': details['created_at'],
            'encrypt_spki': encrypt_spki, 'sign_spki': sign_spki, 'text': 'sgc1.' + code}


# --- messages ----------------------------------------------------------------------------------------------

def seal(plaintext, to_encrypt_spki, me):
    key, iv = AESGCM.generate_key(256), os.urandom(12)
    wrapped = serialization.load_der_public_key(to_encrypt_spki).encrypt(key, OAEP)
    ciphertext = AESGCM(key).encrypt(iv, plaintext, None)
    signature = sign_raw(me['sign_private'], ciphertext)
    envelope = (f'{{"v": 2, "w": "{b64(wrapped)}", "i": "{b64(iv)}", "c": "{b64(ciphertext)}", '
                f'"s": "{b64(signature)}", "f": {json.dumps(me["bundle"]["signing_fingerprint"])}}}')
    return b64(envelope.encode())


def unseal(enc_text, me):
    envelope = json.loads(base64.b64decode(enc_text))
    key = me['encrypt_private'].decrypt(base64.b64decode(envelope['w']), OAEP)
    ciphertext = base64.b64decode(envelope['c'])
    return AESGCM(key).decrypt(base64.b64decode(envelope['i']), ciphertext, None), envelope.get('f'), envelope.get('s'), ciphertext


def message(me, to_card, kind, **parts):
    m = {'v': 1, 'format': MESSAGE_FORMAT, 'id': secrets.token_hex(16), 'kind': kind,
         'from': me['bundle']['signing_fingerprint'], 'to': to_card['bundle']['fingerprint'], 'sent_at': now()}
    m.update({k: v for k, v in parts.items() if v is not None})
    return json.dumps(m, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def open_message(enc_text, me, contacts):
    """(message, trust), trust as SenderTrust: contact, card-inside, unknown, forged, unsigned."""
    plain, signer, signature, ciphertext = unseal(enc_text, me)
    m = json.loads(plain)
    if not signer or not signature: return m, 'unsigned'
    known = next((c for c in contacts.values() if c['bundle']['signing_fingerprint'] == signer), None)
    if known:
        trust = 'contact' if verify_raw(known['sign_spki'], base64.b64decode(signature), ciphertext) else 'forged'
    elif m.get('card'):
        card = read_card(m['card'])
        ok = card['bundle']['signing_fingerprint'] == signer and verify_raw(card['sign_spki'], base64.b64decode(signature), ciphertext)
        trust = 'card-inside' if ok else ('forged' if card['bundle']['signing_fingerprint'] == signer else 'unknown')
    else:
        trust = 'unknown'
    if m.get('from') != signer or m.get('to') != me['bundle']['fingerprint']: trust = 'forged'
    return m, trust


# --- the lane ----------------------------------------------------------------------------------------------

def lane(op, inbox, body, headers=None):
    r = requests.post(f"{inbox['server']}/api/vault/append/{op}/{inbox['vault']}", json=body, headers=headers or {}, timeout=120)
    if r.status_code != 200: raise RuntimeError(f'{op}: status {r.status_code}')
    return r.json()


def make_inbox(home, access_key):
    folder = os.path.join(home, 'inbox')
    quiet = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)          # sgit prints the vault key
    subprocess.run(['sgit', '--base-url', SERVER, '--token', access_key, 'create', 'inbox'], cwd=home, check=True, **quiet)
    open(os.path.join(folder, 'README.md'), 'w').write('An inbox. The messages are in its append lane, sealed.\n')
    subprocess.run(['sgit', 'commit', '-m', 'An inbox'], cwd=folder, check=True, **quiet)
    subprocess.run(['sgit', '--base-url', SERVER, '--token', access_key, 'push'], cwd=folder, check=True, **quiet)
    from sgit_ai.crypto.Vault__Crypto import Vault__Crypto
    vault_key = open(os.path.join(folder, '.sg_vault/local/vault_key')).read().strip()
    write_key = Vault__Crypto().derive_keys_from_vault_key(vault_key)['write_key']
    inbox = {'server': SERVER, 'vault': vault_key.rsplit(':', 1)[1], 'append': secrets.token_hex(24)}
    enum_key = secrets.token_hex(32)
    lane('configure', inbox, {'append_anchors': [hashlib.sha256(inbox['append'].encode()).hexdigest()],
                              'enum_key_hash': hashlib.sha256(enum_key.encode()).hexdigest()},
         {'x-sgraph-vault-write-key': write_key, 'x-sgraph-access-token': access_key})
    return {'address': inbox, 'enum_key': enum_key, 'vault_key': vault_key, 'write_key': write_key}


# --- state -------------------------------------------------------------------------------------------------

def save(home, name, value):
    path = os.path.join(home, name)
    fd = os.open(path + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, json.dumps(value, indent=1).encode()); os.close(fd)
    os.replace(path + '.tmp', path)


def load(home, name, default=None):
    path = os.path.join(home, name)
    return json.load(open(path)) if os.path.exists(path) else default


def me_of(home):
    state = load(home, 'me.json')
    if not state: sys.exit(f'{home} has no person: run setup first.')
    encrypt_private = serialization.load_pem_private_key(state['encrypt_private'].encode(), None)
    sign_private = serialization.load_pem_private_key(state['sign_private'].encode(), None)
    der = lambda k: k.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    encrypt_spki, sign_spki = der(encrypt_private), der(sign_private)
    return {'name': state['name'], 'encrypt_private': encrypt_private, 'sign_private': sign_private,
            'encrypt_spki': encrypt_spki, 'sign_spki': sign_spki, 'bundle': bundle(encrypt_spki, sign_spki, state['name'])}


def contacts_of(home):
    return {fp: read_card(c['card']) | {'met': c['met']} for fp, c in load(home, 'contacts.json', {}).items()}


def add_contact(home, card, met):
    stored = load(home, 'contacts.json', {})
    fp = card['bundle']['fingerprint']
    old = stored.get(fp)
    if old:
        old_card = read_card(old['card'])
        if old_card['sign_spki'] != card['sign_spki'] or old_card['encrypt_spki'] != card['encrypt_spki']:
            raise ValueError('a known fingerprint with other keys: refused')
        if card['created_at'] <= old_card['created_at']: return 'unchanged'
        stored[fp] = {'card': card['text'], 'met': old['met']}
        save(home, 'contacts.json', stored)
        return 'updated'
    stored[fp] = {'card': card['text'], 'met': met}
    save(home, 'contacts.json', stored)
    return 'new'


# --- commands ----------------------------------------------------------------------------------------------

def setup(home, name, with_inbox, access_key):
    if os.path.exists(os.path.join(home, 'me.json')): sys.exit(f'{home} already holds a person.')
    os.makedirs(home, mode=0o700, exist_ok=True)
    pem_private = lambda k: k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
    save(home, 'me.json', {'name': name, 'encrypt_private': pem_private(rsa.generate_private_key(public_exponent=65537, key_size=4096)),
                           'sign_private': pem_private(ec.generate_private_key(ec.SECP256R1()))})
    if with_inbox:
        save(home, 'inbox.json', make_inbox(home, access_key))
        save(home, 'secrets.json', [{'kind': 'access-key', 'name': SERVER, 'server': SERVER, 'value': access_key, 'from': None}])
    print(f"{name}: key {me_of(home)['bundle']['fingerprint']}" + (', inbox ready' if with_inbox else ', no inbox yet'))


def card_text(home):
    inbox = load(home, 'inbox.json')
    return make_card(me_of(home), inbox['address'] if inbox else None)


def invite(home, text, access_key):
    me, newcomer = me_of(home), read_card(text)
    add_contact(home, newcomer, 'by-message')
    secret = {'id': secrets.token_hex(8), 'kind': 'access-key', 'name': SERVER, 'value': access_key, 'server': SERVER, 'version': 1}
    enc = seal(message(me, newcomer, 'secret', card=card_text(home), secret=secret), newcomer['encrypt_spki'], me)
    return 'sgm1.' + b64url(base64.b64decode(enc))


def accept(home, text):
    me = me_of(home)
    code = text[text.index('sgm1.') + 5:].split()[0]
    m, trust = open_message(b64(unb64url(code)), me, contacts_of(home))
    if m['kind'] != 'secret' or m['secret']['kind'] != 'access-key': sys.exit('not an invitation')
    if trust not in ('contact', 'card-inside'): sys.exit(f'the invitation is {trust}: not accepted')
    inviter = read_card(m['card'])
    add_contact(home, inviter, 'by-message')
    secret = m['secret']
    save(home, 'secrets.json', load(home, 'secrets.json', []) + [secret | {'from': inviter['bundle']['fingerprint']}])
    if not load(home, 'inbox.json'):
        save(home, 'inbox.json', make_inbox(home, secret['value']))
    payload = b64(seal(message(me, inviter, 'card', card=card_text(home)), inviter['encrypt_spki'], me).encode())
    lane('write', inviter['inbox'], {'append_token': inviter['inbox']['append'], 'payload': payload})
    print(f"accepted ({trust}): access key from {inviter['name']} kept, inbox ready, card sent to {inviter['name']}")


def send(home, fp, text):
    me, contact = me_of(home), contacts_of(home)[fp]
    payload = b64(seal(message(me, contact, 'text', text=text), contact['encrypt_spki'], me).encode())
    lane('write', contact['inbox'], {'append_token': contact['inbox']['append'], 'payload': payload})
    print(f"sent to {contact['name']}")


def reply(home, text_with_card, answers, text):
    me, to = me_of(home), read_card(text_with_card)
    if not to['inbox']: sys.exit('that card has no inbox to reply to')
    body = message(me, to, 'text', text=text, reply_to=answers, card=card_text(home))
    lane('write', to['inbox'], {'append_token': to['inbox']['append'], 'payload': b64(seal(body, to['encrypt_spki'], me).encode())})
    print(f"replied to {to['name']} about {answers}")


def check(home):
    me, inbox = me_of(home), load(home, 'inbox.json')
    keys = {'x-sgraph-vault-enum-key': inbox['enum_key']}
    entries = lane('list', inbox['address'], {'include_content': False}, keys).get('entries', [])
    kept = load(home, 'messages.json', [])
    for entry in entries:
        files = lane('fetch', inbox['address'], {'inbox': entry['inbox'], 'file_ids': [entry['file_id']]}, keys).get('files', [])
        for f in files:
            m, trust = open_message(base64.b64decode(f['content']).decode(), me, contacts_of(home))
            kept.append({'file_id': f['file_id'], 'trust': trust, 'message': m})
            line = f"{m['kind']} from {m['from']} ({trust})"
            if m['kind'] == 'card' and trust in ('contact', 'card-inside'):
                card = read_card(m['card'])
                line += f": {card['name']}, contact {add_contact(home, card, 'through-inbox')}, inbox {'yes' if card['inbox'] else 'no'}"
            elif m['kind'] == 'text':
                line += f": {m['text']!r}"
            print(line)
        save(home, 'messages.json', kept)
        lane('mark-processed', inbox['address'], {'inbox': entry['inbox'], 'file_ids': [entry['file_id']]}, keys)
    print(f'{len(entries)} message(s)')


def destroy(home, access_key):
    inbox = load(home, 'inbox.json')
    r = requests.delete(f"{inbox['address']['server']}/api/vault/destroy/{inbox['address']['vault']}",
                        json={'vault_id': inbox['address']['vault']},
                        headers={'x-sgraph-vault-write-key': inbox['write_key'], 'x-sgraph-access-token': access_key}, timeout=60)
    print(f"destroy {inbox['address']['vault']}: status {r.status_code}")


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--home', required=True)
    p.add_argument('--access-key', default=os.environ.get('SGIT_TOKEN', ''))
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('setup'); s.add_argument('name'); s.add_argument('--inbox', action='store_true')
    sub.add_parser('card')
    s = sub.add_parser('add'); s.add_argument('card')
    s = sub.add_parser('invite'); s.add_argument('card')
    s = sub.add_parser('accept'); s.add_argument('sealed')
    s = sub.add_parser('send'); s.add_argument('fingerprint'); s.add_argument('text')
    s = sub.add_parser('reply'); s.add_argument('card'); s.add_argument('id'); s.add_argument('text')
    sub.add_parser('check'); sub.add_parser('destroy')
    a = p.parse_args()
    if a.cmd == 'setup': setup(a.home, a.name, a.inbox, a.access_key)
    elif a.cmd == 'card': print(card_text(a.home))
    elif a.cmd == 'add': print(add_contact(a.home, read_card(a.card), 'by-message'))
    elif a.cmd == 'invite': print(invite(a.home, a.card, a.access_key))
    elif a.cmd == 'accept': accept(a.home, a.sealed)
    elif a.cmd == 'send': send(a.home, a.fingerprint, a.text)
    elif a.cmd == 'reply': reply(a.home, a.card, a.id, a.text)
    elif a.cmd == 'check': check(a.home)
    elif a.cmd == 'destroy': destroy(a.home, a.access_key)


if __name__ == '__main__':
    main()
