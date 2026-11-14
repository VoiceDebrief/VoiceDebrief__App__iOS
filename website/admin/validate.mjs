// The gate. No dependencies, no network. Adapted from VoiceDebrief MeetScribe's validate.mjs.
//   node website/admin/validate.mjs
// 1. every generated file is up to date (build.mjs --check)
// 2. every index.md has its index.html, and every page is in build.mjs's list
// 3. every relative link in the site's HTML, markdown and llms.txt resolves, including #anchors in HTML
// 4. no key-shaped string anywhere in the repository (the ciphertext rule): API keys, private keys,
//    sgit vault keys. Packages/SGitVault/Tests/ is exempt: its vaults and keys are throwaway fixtures.
// 5. house style on the site: no em-dashes
// 6. no script on any page: this site is static
// 7. the version file is vMAJOR.MINOR.PATCH (CI writes it; nobody else does)
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const SITE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');   // website/
const REPO_ROOT = resolve(SITE_ROOT, '..');
const fails = [];
const fail = (msg) => fails.push(msg);

const walk = (d) => readdirSync(d).flatMap(n => {
  if (['.git', 'node_modules', '.build', 'DerivedData'].includes(n)) return [];
  const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p];
});
const site = walk(SITE_ROOT);
const rel = (p) => relative(REPO_ROOT, p);

// 1
try { execFileSync(process.execPath, [join(SITE_ROOT, 'admin/build.mjs'), '--check'], { stdio: 'pipe' }); }
catch (e) { fail(`generated files out of date:\n${e.stderr}`); }

// 2
const listed = [...readFileSync(join(SITE_ROOT, 'admin/build.mjs'), 'utf8').matchAll(/path: '([^']*)'/g)].map(m => m[1]);
for (const md of site.filter(f => f.endsWith('index.md'))) {
  const dir = relative(SITE_ROOT, dirname(md)) || '';
  if (!listed.includes(dir) && !/^(versions\/v\d+\.\d+\.\d+|guides\/[a-z0-9-]+)$/.test(dir)) fail(`${rel(md)} is not in build.mjs's page list`);
  if (!existsSync(join(dirname(md), 'index.html'))) fail(`${rel(md)} has no index.html`);
}

// 3
const anchors = new Map();
const idsOf = (html) => { if (!anchors.has(html)) anchors.set(html, new Set([...readFileSync(html, 'utf8').matchAll(/ id="([^"]+)"/g)].map(m => m[1]))); return anchors.get(html); };
const SITE = 'https://' + readFileSync(join(SITE_ROOT, 'CNAME'), 'utf8').trim();
const checkLink = (from, href) => {
  if (href === SITE || href.startsWith(SITE + '/')) { from = join(SITE_ROOT, 'index.html'); href = href.slice(SITE.length + 1) || 'index.html'; }   // our own absolute URLs must resolve here too
  if (/^([a-z]+:|\/\/)/i.test(href)) return;
  const [path, frag] = href.split('#');
  const target = path ? resolve(dirname(from), decodeURI(path)) : from;
  if (!existsSync(target)) return fail(`${rel(from)}: broken link ${href}`);
  if (frag && target.endsWith('.html') && !idsOf(target).has(frag)) fail(`${rel(from)}: missing anchor ${href}`);
};
const stripCode = (s) => s.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
for (const f of site) {
  if (f.endsWith('.html')) for (const m of readFileSync(f, 'utf8').matchAll(/(?:href|src)="([^"]+)"/g)) checkLink(f, m[1].replace(/&amp;/g, '&'));
  if (f.endsWith('.md')) for (const m of stripCode(readFileSync(f, 'utf8')).matchAll(/\]\(([^)\s]+)\)/g)) checkLink(f, m[1]);
}
for (const m of readFileSync(join(SITE_ROOT, 'llms.txt'), 'utf8').matchAll(/https?:\/\/[^\s)>\]]+/g)) checkLink(join(SITE_ROOT, 'llms.txt'), m[0].replace(/[.,;]$/, ''));

// 4
const SECRET = new RegExp([
  'sk-or-v1-[0-9a-f]{32,}', 'sk-(?:proj-)?[A-Za-z0-9_-]{32,}', 'gh[pousr]_[A-Za-z0-9]{30,}', 'AKIA[0-9A-Z]{16}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----',
  'sgit_private_' + 'vault_[a-z0-9]{24,}:[a-z0-9]{4,24}',          // split so this file holds no key-shaped literal
].join('|'));
for (const f of walk(REPO_ROOT)) {
  const r = rel(f);
  if (/\.(png|jpg|jpeg|zip|ico|ttf)$/.test(f)) continue;
  if (r.startsWith('Packages/SGitVault/Tests/')) continue;
  const m = readFileSync(f, 'utf8').match(SECRET);
  if (m) fail(`${r}: key-shaped string (${m[0].slice(0, 12)}...)`);
}

// 5, 6
for (const f of site.filter(f => /\.(md|html|txt)$/.test(f))) {
  const s = readFileSync(f, 'utf8');
  if (s.includes('—')) fail(`${rel(f)}: em-dash (house style)`);
  if (f.endsWith('.html') && /<script/i.test(s)) fail(`${rel(f)}: a script on a static page`);
}

// 7
const version = readFileSync(join(REPO_ROOT, 'version'), 'utf8').trim();
if (!/^v\d+\.\d+\.\d+$/.test(version)) fail(`version file: "${version}" is not vMAJOR.MINOR.PATCH`);

if (fails.length) { console.error(`validate: ${fails.length} problem(s)\n- ${fails.join('\n- ')}`); process.exit(1); }
console.log(`validate: ok (${site.length} site files, ${version})`);
