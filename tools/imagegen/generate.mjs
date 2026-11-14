// Remakes the generated images of both apps and the site from images.json.
// Usage: OPENROUTER_API_KEY=... node tools/imagegen/generate.mjs [id ...]   (no ids: only missing outputs)
//        node tools/imagegen/generate.mjs --force id ...                     (remake even if present)
// The key is read from the environment and never written anywhere. Each image's model and prompt are
// in images.json beside this file, so any image can be remade or replaced.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';

const here = dirname(new URL(import.meta.url).pathname);
const root = resolve(here, '../..');
const manifest = JSON.parse(readFileSync(join(here, 'images.json'), 'utf8'));
const args = process.argv.slice(2);
const force = args.includes('--force');
const ids = args.filter(a => !a.startsWith('--'));
const key = process.env.OPENROUTER_API_KEY;
if (!key) { console.error('OPENROUTER_API_KEY is not set'); process.exit(1); }

function promptFor(image) {
  const style = manifest.styles[image.style];
  const accent = image.accent ? ` The section's accent colour is ${image.accent}.` : '';
  return `${image.prompt}\n\n${style}${accent}`;
}

async function generate(image) {
  const body = {
    model: image.model ?? manifest.defaultModel,
    modalities: ['image', 'text'],
    messages: [{ role: 'user', content: promptFor(image) }],
    image_config: { aspect_ratio: image.aspect ?? '1:1' },
    usage: { include: true },
  };
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${image.id}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
  const json = await res.json();
  const url = json.choices?.[0]?.message?.images?.[0]?.image_url?.url;
  if (!url) throw new Error(`${image.id}: no image in the response: ${JSON.stringify(json).slice(0, 300)}`);
  image.cost = json.usage?.cost ?? null; // dollars, as OpenRouter reports it
  image.made = new Date().toISOString().slice(0, 10);
  image.modelUsed = json.model ?? body.model;
  return Buffer.from(url.split(',')[1], 'base64');
}

function finish(image, raw) {
  const out = join(root, image.out);
  mkdirSync(dirname(out), { recursive: true });
  const tmp = join(tmpdir(), `imagegen-${image.id}.png`);
  writeFileSync(tmp, raw);
  const [w, h] = image.size;
  const fit = ['-resize', `${w}x${h}^`, '-gravity', 'center', '-extent', `${w}x${h}`, '-strip'];
  if (out.endsWith('.jpg')) execFileSync('convert', [tmp, ...fit, '-quality', String(image.quality ?? 78), '-sampling-factor', '4:2:0', '-interlace', 'JPEG', out]);
  else execFileSync('convert', [tmp, ...fit, '-alpha', 'off', out]); // app icons: no transparency
  console.log(`${image.id} -> ${image.out}`);
}

const todo = manifest.images.filter(i => ids.length ? ids.includes(i.id) : (force || !existsSync(join(root, i.out))));
const results = await Promise.allSettled(todo.map(async i => finish(i, await generate(i))));
for (const r of results) if (r.status === 'rejected') console.error(String(r.reason));
// Write back what each image cost and which model made it, beside its prompt.
writeFileSync(join(here, 'images.json'), JSON.stringify(manifest, null, 2) + '\n');
for (const i of todo) if (i.cost != null) console.log(`${i.id}: $${i.cost}`);
