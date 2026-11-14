#!/usr/bin/env python3
"""people.py against message.js and Swift. Keys are made for the run and protect nothing.

    people_py_interop.py local <lib> <work>   people.py and message.js, both ways, here and now
    people_py_interop.py make <work>          P (people.py's key), P's card, and a message from P to R (made by msgjs make)
    people_py_interop.py read <work>          open what Swift sealed to P, and read Swift's card
"""
import base64, importlib.util, json, os, subprocess, sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('people', os.path.join(here, '../../tools/people/people.py'))
people = importlib.util.module_from_spec(spec); spec.loader.exec_module(people)
der = lambda k: k.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
pem_private = lambda k: k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()


def person(name, enc=None, sig=None):
    enc = enc or rsa.generate_private_key(public_exponent=65537, key_size=4096)
    sig = sig or ec.generate_private_key(ec.SECP256R1())
    p = {'name': name, 'encrypt_private': enc, 'sign_private': sig, 'encrypt_spki': der(enc), 'sign_spki': der(sig)}
    p['bundle'] = people.bundle(p['encrypt_spki'], p['sign_spki'], name)
    return p


def contact_of(b):
    return {'bundle': b, 'sign_spki': people.spki_of(b['sign']), 'encrypt_spki': people.spki_of(b['encrypt'])}


def from_msgjs(path):
    j = json.load(open(path))
    return contact_of(j['bundle'])


cmd = sys.argv[1]
if cmd == 'local':
    lib, work = sys.argv[2], sys.argv[3]
    os.makedirs(work, exist_ok=True)
    subprocess.run(['node', os.path.join(here, 'msgjs.mjs'), 'make', lib, work], check=True)
    # people.py plays R, with R's private key from message.js (PKCS#8 bytes)
    r = json.load(open(os.path.join(work, 'recipient-r.json')))
    load = lambda b: serialization.load_der_private_key(base64.b64decode(b), None)
    me = person('R', load(r['encrypt']), load(r['sign']))
    n = from_msgjs(os.path.join(work, 'msgjs-n.json'))
    m, trust = people.open_message(people.from_m1(open(os.path.join(work, 'msgjs-to-r.m1')).read()), me, {n['bundle']['fingerprint']: n})
    assert trust == 'contact' and m['grant']['token'] == 'not-a-real-token', (trust, m)
    print(f'people.py opened message.js\'s message: {trust}, {m["text"]!r}')
    secret = {'id': 's1', 'kind': 'access-key', 'name': 'dev', 'value': 'not-a-real-token', 'server': 'https://dev.send.sgraph.ai', 'version': 1}
    sealed = people.seal(people.message(me, n, 'secret', secret=secret, reply_to='note-1'), n['encrypt_spki'], me)
    open(os.path.join(work, 'swift-to-msgjs.m1'), 'w').write(people.m1_code(sealed, n['bundle']['signing_fingerprint']))
    subprocess.run(['node', os.path.join(here, 'msgjs.mjs'), 'read', lib, work], check=True)
elif cmd == 'make':
    work = sys.argv[2]
    p = person('people.py (throwaway)')
    open(os.path.join(work, 'people-py-p.json'), 'w').write(json.dumps({'encrypt': pem_private(p['encrypt_private']), 'sign': pem_private(p['sign_private'])}))
    r = from_msgjs(os.path.join(work, 'recipient-r.json'))
    inbox = {'server': 'https://dev.send.sgraph.ai', 'vault': 'interop1', 'append': '0123456789abcdef' * 3}
    card = people.make_card(p, inbox)
    open(os.path.join(work, 'people-py-p.card'), 'w').write(card)
    note = people.message(p, r, 'text', text='from people.py: Zoë', card=card, reply_to='note-7')
    open(os.path.join(work, 'people-py-to-r.m1'), 'w').write(people.m1_code(people.seal(note, r['encrypt_spki'], p), r['bundle']['signing_fingerprint']))
    print(f'people.py: P {p["bundle"]["signing_fingerprint"]}, its card, a message from P to R')
elif cmd == 'read':
    work = sys.argv[2]
    keys = json.load(open(os.path.join(work, 'people-py-p.json')))
    p = person('people.py (throwaway)', serialization.load_pem_private_key(keys['encrypt'].encode(), None),
               serialization.load_pem_private_key(keys['sign'].encode(), None))
    swift_card = people.read_card(open(os.path.join(work, 'swift-r.card')).read())
    r = from_msgjs(os.path.join(work, 'recipient-r.json'))
    assert swift_card['bundle']['fingerprint'] == r['bundle']['fingerprint'], 'Swift\'s card is not R\'s key'
    m, trust = people.open_message(base64.b64decode(open(os.path.join(work, 'swift-to-p.lane')).read()).decode(), p,
                                   {r['bundle']['fingerprint']: r})
    assert trust == 'contact' and m['type'] == 'card' and m['reply_to'] == 'note-7', (trust, m)
    assert people.read_card(m['card'])['inbox']['vault'] == 'swiftinbox', m
    print(f'people.py opened what Swift put in its lane: {trust}, a {m["type"]} answering {m["reply_to"]}; Swift\'s card checks')
