#!/usr/bin/env python3
"""sgit reads what Swift made.

    sgit_reads_swift.py <folder Swift wrote> <the home folder sgit_make.py made its key in> <sgit-made.json>

Two key stores are used. In the one sgit made, Swift's bundle is a contact: sgit imports it, verifies Swift's
detached signature, and opens the envelope Swift sealed to sgit's key. In a fresh one, the key store Swift wrote
is sgit's own key: sgit lists it, exports it, signs with it and opens an envelope sealed to it.
python-cryptography, which sgit is built on, also loads Swift's bare PKCS#8 private keys.
Prints one markdown line per check; exits 1 at the first that fails.
"""
import base64, json, os, shutil, subprocess, sys, tempfile

from cryptography.hazmat.primitives import serialization


def main():
    swift, sgit_home, made_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(made_path, encoding='utf-8') as f:
        made = json.load(f)

    def read(name, binary=False):
        with open(os.path.join(swift, name), 'rb' if binary else 'r', **({} if binary else {'encoding': 'utf-8'})) as f:
            return f.read()

    def sgit(home, *args, ok=True, passphrase=made['passphrase']):
        env = dict(os.environ, HOME=home, SG_SEND_PASSPHRASE=passphrase)
        done = subprocess.run(['sgit', 'pki', *args], env=env, cwd=swift, capture_output=True)
        if ok and done.returncode != 0:
            sys.exit(f'FAILED: sgit pki {" ".join(args)}\n{done.stdout.decode()}\n{done.stderr.decode()}')
        return done

    def check(ok, what):
        if not ok:
            sys.exit(f'FAILED: {what}')
        print(f'- Swift → sgit: {what}')

    bundle = json.loads(read('bundle.json'))
    message = read('message.txt', binary=True)

    # 1. Swift's bundle as a contact of the key sgit made.
    out = sgit(sgit_home, 'import', os.path.join(swift, 'bundle.json')).stdout.decode()
    check(bundle['fingerprint'] in out, f'`sgit pki import` reads the bundle and computes the same fingerprint ({bundle["fingerprint"]})')
    report = json.loads(sgit(sgit_home, 'verify', 'message.txt', 'message.txt.sig', '--json').stdout.decode())
    check(report['valid'] is True and report['signing_fingerprint'] == bundle['signing_fingerprint'],
          f'`sgit pki verify` accepts the detached signature ({bundle["signing_fingerprint"]})')
    changed = os.path.join(tempfile.mkdtemp(), 'changed.txt')
    with open(changed, 'wb') as f:
        f.write(message + b'!')
    check(sgit(sgit_home, 'verify', changed, os.path.join(swift, 'message.txt.sig'), ok=False).returncode != 0,
          '`sgit pki verify` refuses the same signature over changed bytes')
    done = sgit(sgit_home, 'decrypt', 'to-sgit.enc', '--fingerprint', made['fingerprint'], '--output', '-')
    check(done.stdout == message, '`sgit pki decrypt` opens the envelope sealed to sgit\'s key, to the exact bytes')
    check(b'Signature verified' in done.stderr and bundle['signing_fingerprint'].encode() in done.stderr,
          'and reports the envelope\'s signature as verified, by Swift\'s signing key')

    # 2. The key store Swift wrote, as sgit's own key.
    home = tempfile.mkdtemp()
    shutil.copytree(os.path.join(swift, 'keystore'), os.path.join(home, '.sg-send', 'keys'))
    passphrase = read('keystore-passphrase.txt')
    listed = sgit(home, 'list', passphrase=passphrase).stdout.decode()
    check(bundle['fingerprint'] in listed, '`sgit pki list` shows the key store Swift wrote')
    exported = json.loads(sgit(home, 'export', bundle['fingerprint'], passphrase=passphrase).stdout.decode())
    check(exported == bundle, '`sgit pki export` of it is the bundle Swift wrote, field for field')
    done = sgit(home, 'decrypt', 'to-self.enc', '--fingerprint', bundle['fingerprint'], '--output', '-', passphrase=passphrase)
    check(done.stdout == message and b'Signature verified' in done.stderr,
          '`sgit pki decrypt` opens an envelope with the private key Swift made (PBES2 written by Swift), signature verified')
    done = sgit(home, 'decrypt', 'unsigned-to-self.enc', '--fingerprint', bundle['fingerprint'], '--output', '-', passphrase=passphrase)
    check(done.stdout == message and b'Signature' not in done.stderr, 'an unsigned envelope opens and is not reported as signed')
    work = tempfile.mkdtemp()
    target = os.path.join(work, 'note.txt')
    with open(target, 'wb') as f:
        f.write(b'signed by sgit with a key Swift made\n')
    sgit(home, 'sign', target, '--fingerprint', bundle['fingerprint'], passphrase=passphrase)
    check(sgit(home, 'verify', target, target + '.sig', passphrase=passphrase).returncode == 0,
          '`sgit pki sign` signs with the signing key Swift made, and verifies it')
    check(sgit(home, 'decrypt', 'to-self.enc', '--fingerprint', bundle['fingerprint'], '--output', '-', ok=False, passphrase='wrong').returncode != 0,
          'a wrong passphrase is refused')

    # 3. The bare PKCS#8 private keys.
    spki = lambda key: key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    enc = serialization.load_der_private_key(base64.b64decode(read('private-encrypt.pkcs8.b64')), password=None)
    sig = serialization.load_der_private_key(base64.b64decode(read('private-sign.pkcs8.b64')), password=None)
    check(enc.key_size == 4096 and enc.public_key().public_numbers().e == 65537, 'the encryption key is RSA 4096 with e = 65537')
    check(spki(enc) == bundle['encrypt'] and spki(sig) == bundle['sign'],
          'python-cryptography loads both PKCS#8 private keys and derives the PEM public keys in the bundle, byte for byte')


if __name__ == '__main__':
    main()
