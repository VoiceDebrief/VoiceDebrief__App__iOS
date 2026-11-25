// lane.entry/2: a second, independent reader in JavaScript (Node 20+, WebCrypto only), run against the same vectors
// as the Python reference. It checks what a browser reader must get right: canonical JSON as JSON.stringify writes it
// with keys sorted by UTF-16 code unit, the entry hash, the P-256 signature in raw r||s (WebCrypto's own form), and the
// one-layer wire with the hybrid envelope v2. Apache 2.0.
//   node tools/lanes/check_vectors.mjs website/lanes/entry-v2/vectors.json
import { readFileSync } from 'node:fs'
const { subtle } = globalThis.crypto
const te = new TextEncoder(), td = new TextDecoder()
const fromB64 = s => Uint8Array.from(Buffer.from(s, 'base64'))
const fromB64u = s => Uint8Array.from(Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64'))
const hex = b => Buffer.from(b).toString('hex')

const sortKeys = v => Array.isArray(v) ? v.map(sortKeys)
  : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])])) : v   // .sort() is by UTF-16 code unit
const canonical = v => JSON.stringify(sortKeys(v))
const sha = async bytes => 'sha256:' + hex(await subtle.digest('SHA-256', bytes))
const withoutProof = e => { const { proof, ...rest } = e; return rest }

async function checkEntry(e) {
  if (e.schema !== 'lane.entry/2') throw 'E_SCHEMA'
  const der = fromB64u(e.author.spki)
  if (e.author.key !== 'p256:' + hex(await subtle.digest('SHA-256', der))) throw 'E_KEY'
  const key = await subtle.importKey('spki', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'])
  const sig = fromB64u(e.proof.sig)
  if (sig.length !== 64) throw 'E_SIG'
  const ok = await subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, te.encode(canonical(withoutProof(e))))
  if (!ok) throw 'E_SIG'
}

const v = JSON.parse(readFileSync(process.argv[2], 'utf8'))
let n = 0
for (const c of v.canonical) { if (canonical(c.value) !== c.text) throw new Error('canonical: ' + c.why); n++ }
const rsa = await subtle.importKey('pkcs8', fromB64(v.keys.recipient_rsa_private_pkcs8_b64), { name: 'RSA-OAEP', hash: 'SHA-256' }, false, ['decrypt'])
for (const p of v.positive) {
  if (p.entry) {
    await checkEntry(p.entry)
    if (await sha(te.encode(canonical(p.entry))) !== p.hash) throw new Error('hash: ' + p.name)
  } else if (p.chain) {
    for (const e of p.chain) await checkEntry(e)
  } else {
    const env = JSON.parse(td.decode(fromB64(p.payload)))
    const aes = await subtle.importKey('raw', await subtle.decrypt({ name: 'RSA-OAEP' }, rsa, fromB64(env.w)), 'AES-GCM', false, ['decrypt'])
    const plain = new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv: fromB64(env.i) }, aes, fromB64(env.c)))
    const entry = JSON.parse(td.decode(plain))
    if (canonical(entry) !== td.decode(plain)) throw new Error('sealed entry not canonical')
    await checkEntry(entry)
    if (await sha(plain) !== p.opens_to_hash) throw new Error('wire: ' + p.name)
  }
  n++
}
for (const x of v.negative.filter(x => x.entry && ['E_SIG', 'E_KEY', 'E_SCHEMA'].includes(x.code))) {
  try { await checkEntry(x.entry) } catch (code) { if (code === x.code) { n++; continue } throw new Error(`${x.name}: ${code}, expected ${x.code}`) }
  throw new Error(`${x.name}: accepted`)
}
console.log(`lane.entry/2 vectors, JavaScript reader: ${n} checks as expected`)
