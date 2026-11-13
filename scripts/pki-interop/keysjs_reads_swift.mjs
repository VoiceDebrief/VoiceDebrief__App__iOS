// pki.sgit.ai's own code reads what Swift made: the bundle, the k1 code, the private keys, a detached signature,
// an envelope, the vouching statement, canonical forms and the sign-in request.
//
//   node keysjs_reads_swift.mjs <folder holding keys.js …> <folder Swift wrote> <keysjs-made.json>
//
// Prints one markdown line per check; exits 1 at the first that fails.
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { resolve, join } from 'node:path'
import { isDeepStrictEqual } from 'node:util'

const [lib, swift, madePath] = process.argv.slice(2)
if (!lib || !swift || !madePath) { console.error('usage: keysjs_reads_swift.mjs <lib folder> <swift folder> <keysjs-made.json>'); process.exit(2) }
const load = name => import(pathToFileURL(resolve(lib, name)).href)
const K = await load('keys.js'), M = await load('message.js'), DG = await load('delegation.js')
const read = name => readFileSync(join(swift, name), 'utf8')
const check = (ok, what) => { if (!ok) { console.error('FAILED: ' + what); process.exit(1) } console.log('- Swift → keys.js: ' + what) }

const made = JSON.parse(readFileSync(madePath, 'utf8'))
const person = JSON.parse(made.identity)
const bundle = JSON.parse(read('bundle.json'))

const problems = await K.checkBundle(bundle)
check(problems.length === 0, `checkBundle finds nothing wrong with the bundle (${bundle.fingerprint}, ${bundle.signing_fingerprint})${problems.length ? ': ' + problems.join('; ') : ''}`)
check(isDeepStrictEqual(await M.parseKeyCode(read('k1.txt')), bundle), 'parseKeyCode reads the k1 code back to the bundle')
check(M.keyCode(bundle).code === read('k1.txt'), 'keyCode writes the same k1 code')

const encPkcs8 = K.unb64(read('private-encrypt.pkcs8.b64')), signPkcs8 = K.unb64(read('private-sign.pkcs8.b64'))
check(isDeepStrictEqual(await K.publicFromPrivate(encPkcs8, signPkcs8, bundle.label), bundle), 'WebCrypto imports both PKCS#8 private keys and recomputes the bundle')

const message = readFileSync(join(swift, 'message.txt'))
const sig = JSON.parse(read('message.txt.sig'))
check(sig.fingerprint === bundle.signing_fingerprint && await K.verifyBytes(bundle.sign, K.unb64(sig.signature), message), 'the detached signature verifies (raw r||s, 64 bytes)')

const opened = await K.unseal(K.unb64(person.private.encrypt), read('to-keysjs.enc'), [bundle])
check(opened.text === message.toString('utf8') && opened.signed && opened.verified === true, 'unseal opens the envelope sealed to a keys.js key, and its signature is the bundle\'s')
const mine = await K.unseal(encPkcs8, read('to-self.enc'), [bundle])
check(mine.text === message.toString('utf8') && mine.verified === true, 'unseal opens an envelope with the private key Swift made')

const statement = JSON.parse(read('statement.json'))
check(await K.verifyStatement(statement, bundle.sign), 'verifyStatement accepts the vouching statement')
check(K.fromUtf8(K.canonicalBytes(statement)) === read('statement-canonical.txt'), 'its canonical bytes are the ones Swift signed')
check(await K.statementId(statement) === read('statement-id.txt'), 'its statement id is the one Swift computed')
check(!await K.verifyStatement({ ...statement, created_at: '2026-11-13T10:00:01Z' }, bundle.sign), 'a changed statement is refused')
check(statement.signer === bundle.signing_fingerprint && isDeepStrictEqual(statement.body.bundle, bundle) && await K.fingerprint(statement.body.key) === statement.body.key_fingerprint,
      'it names the user key as signer, carries the bundle, and the device fingerprint is the device key\'s')

const cases = JSON.parse(read('canon-cases.json'))
check(cases.length > 0 && cases.every(c => K.canon(c.value) === c.canon), `${cases.length} canonical forms written by Swift are keys.js's, byte for byte`)

const req = await DG.parseRequest(read('request.json'))
check(isDeepStrictEqual(req.bundle, bundle) && req.client === 'https://ios.app.voicedebrief.ai', 'parseRequest accepts the sign-in request, and reads the key in it back to the bundle')
const url = read('request-url.txt'), m = /[#&]r=([A-Za-z0-9_-]+)/.exec(url)
check(url.startsWith('https://pki.sgit.ai/authorize/index.html#r=') && m && K.fromUtf8(K.unb64url(m[1])) === read('request.json'), 'the authorize address carries that request')
const d = await DG.makeDelegation({ bundle: person.bundle, private: { sign: K.unb64(person.private.sign) } }, req, { name: 'Fixture Person' })
check(d.to === bundle.signing_fingerprint && await K.verifyStatement(d, person.bundle.sign), 'makeDelegation signs a delegation for the key Swift made')

for (const name of ['private_key.pem', 'signing_private.pem']) {
    const folder = bundle.fingerprint.replace(':', '_')
    const pkcs8 = await K.decryptPrivate(read(`keystore/${folder}/${name}`), read('keystore-passphrase.txt'))
    check(isDeepStrictEqual([...pkcs8], [...(name === 'private_key.pem' ? encPkcs8 : signPkcs8)]), `decryptPrivate opens ${name} as Swift encrypted it (PBES2)`)
}
