// pki.sgit.ai's own message.js against SGitPeople's formats. Every key here is made for the run and protects nothing.
//
//   node msgjs.mjs make <lib folder> <work folder>   two keys (N, the sender, and R, a recipient whose private key is
//                                                    passed on so Swift can be R), and a message from N to R as an m1 code
//   node msgjs.mjs read <lib folder> <work folder>   open <work>/swift-to-msgjs.m1 with N: fails unless every check passes
import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { resolve, join } from 'node:path'

const [cmd, lib, work] = process.argv.slice(2)
const load = name => import(pathToFileURL(resolve(lib, name)).href)
const K = await load('keys.js'), M = await load('message.js')
const save = (name, id) => writeFileSync(join(work, name), JSON.stringify({ bundle: id.bundle, encrypt: K.b64(id.private.encrypt), sign: K.b64(id.private.sign) }))
const restore = name => { const id = JSON.parse(readFileSync(join(work, name), 'utf8')); return { bundle: id.bundle, private: { encrypt: K.unb64(id.encrypt), sign: K.unb64(id.sign) } } }

if (cmd === 'make') {
    const n = await K.generate('message.js sender (throwaway)'), r = await K.generate('recipient for Swift (throwaway)')
    save('msgjs-n.json', n)
    save('recipient-r.json', r)
    const msg = await M.compose({ to: r.bundle, from: n, text: 'from message.js: é 日本', subject: 'interop',
                                  grant: { endpoint: 'https://dev.send.sgraph.ai', token: 'not-a-real-token', name: 'dev' } })
    writeFileSync(join(work, 'msgjs-to-r.m1'), (await M.sealMessage(msg, r.bundle, n)).code)
    console.log(`message.js: N ${n.bundle.signing_fingerprint}, R ${r.bundle.signing_fingerprint}, a message from N to R`)
} else if (cmd === 'read') {
    const n = restore('msgjs-n.json'), r = JSON.parse(readFileSync(join(work, 'recipient-r.json'), 'utf8')).bundle
    const parsed = M.parseCode(readFileSync(join(work, 'swift-to-msgjs.m1'), 'utf8'))
    if (!parsed) throw new Error('message.js does not read the m1 code')
    const opened = await M.openMessage(parsed.enc, [n], new Map([[r.signing_fingerprint, r]]))
    const out = { envelopeVerified: opened.envelope.verified, verified: opened.verified, problems: opened.problems,
                  text: opened.msg.text, type: opened.msg.type, grant: opened.msg.grant || null }
    console.log('message.js opened what Swift sealed:', JSON.stringify(out))
    if (opened.verified !== true || opened.envelope.verified !== true || opened.problems.length || !out.grant) process.exit(1)
} else { console.error('usage: msgjs.mjs make|read <lib> <work>'); process.exit(2) }
