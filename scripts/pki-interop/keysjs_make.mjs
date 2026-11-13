// What pki.sgit.ai's own code makes, for Swift to read: an identity, its k1 code, a private key under a
// passphrase, a signed statement, canonical forms, a sealed message, and a sign-in (request, delegation, answer).
// Every key here is made for this file and protects nothing.
//
//   node keysjs_make.mjs <folder holding keys.js, message.js, delegation.js> <out.json>
import { writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { resolve } from 'node:path'

const [lib, out] = process.argv.slice(2)
if (!lib || !out) { console.error('usage: keysjs_make.mjs <lib folder> <out.json>'); process.exit(2) }
const load = name => import(pathToFileURL(resolve(lib, name)).href)
const K = await load('keys.js'), M = await load('message.js'), DG = await load('delegation.js')

const flat = id => JSON.stringify({ bundle: id.bundle, private: { encrypt: K.b64(id.private.encrypt), sign: K.b64(id.private.sign) }, created: id.created })
const person = await K.generate('keys.js interop (throwaway)')
const browser = await K.generate('browser key (throwaway)')
const passphrase = 'throwaway passphrase, protects nothing'

const statement = await K.signStatement({
    v: 1, type: 'identity', registry: 'pki.sgit.ai', record: person.bundle.signing_fingerprint, signer: person.bundle.signing_fingerprint,
    created_at: '2026-11-13T10:00:00Z',
    body: { kind: 'person', name: 'Fixture: “Zoë” / <b>\u0001\t\n\\ "q" é 日本 😀', about: '', private_key_published: true, n: 0, neg: -12, list: [1, 'two', null, true, false, { z: 1, a: 2 }], bundle: person.bundle },
}, person.private.sign)

const cases = [
    { b: 1, a: 2, 'é': 3, Z: 4, '😀': 5, '￿': 6, aa: 7, '': 8 },
    ['', 'a/b', '\u007f', ' ', '\u0000', '\u001f', '\\', '"', '</script>'],
    { nested: { y: [], x: {} }, n: 9007199254740991, m: -1, t: true, f: false, z: null },
    'plain', 0, null, true,
].map(value => ({ value, canon: K.canon(value) }))

const text = 'sealed by keys.js: “quotes”, é, 日本, 😀\n'
const sealed = await K.seal(person.bundle, text, { sign: person.private.sign, fingerprint: person.bundle.signing_fingerprint })

// The sign-in, as sso.js asks for it and authorize.js answers it.
const client = 'https://ios.app.voicedebrief.ai', nonce = K.b64url(globalThis.crypto.getRandomValues(new Uint8Array(24)))
const request = { v: 1, kind: DG.REQUEST, client, return: client + '/identity/return/', key: M.keyCode(browser.bundle).code, can: ['identity', 'sign:commit'], days: 90, nonce, label: 'VoiceDebrief on a test device' }
const req = await DG.parseRequest(JSON.stringify(request))
const from = Date.UTC(2026, 10, 13)
const delegation = await DG.makeDelegation(person, req, { name: 'Fixture Person', from })
const answer = { v: 1, kind: DG.AUTHORIZED, nonce, delegation, identity: { fp: delegation.iss, name: delegation.iss_name, id: `https://pki.sgit.ai/id/${K.dirOf(delegation.iss)}.json` } }
const denied = { v: 1, kind: DG.DENIED, nonce }
const frag = o => 'pki=' + K.b64url(K.utf8(JSON.stringify(o)))

writeFileSync(out, JSON.stringify({
    _about: 'Made by pki.sgit.ai keys.js, message.js and delegation.js (lib v0.2.28) through scripts/pki-interop/keysjs_make.mjs. Throwaway keys: they protect nothing.',
    identity: flat(person), k1: M.keyCode(person.bundle).code,
    passphrase, 'signing_private.pem': await K.encryptPrivate(person.private.sign, passphrase, 2000), 'private_key.pem': await K.encryptPrivate(person.private.encrypt, passphrase, 2000),
    statement: JSON.stringify(statement), statement_id: await K.statementId(statement), statement_canonical: K.fromUtf8(K.canonicalBytes(statement)),
    canon_cases: JSON.stringify(cases),
    sealed_text: text, 'sealed.enc': sealed,
    browser: flat(browser), request: JSON.stringify(request), delegation: JSON.stringify(delegation), delegation_id: await DG.delegationId(delegation),
    answer: client + '/identity/return/#' + frag(answer), denied: client + '/identity/return/#' + frag(denied), today: '2026-11-20',
}, null, 1) + '\n')
console.log(`keys.js made ${out}: ${person.bundle.signing_fingerprint} (person), ${browser.bundle.signing_fingerprint} (browser key)`)
