// Builds the site: every page's index.md is the source, and index.html beside it is generated from it.
// No dependencies, no network. Ported from VoiceDebrief MeetScribe's admin/build/build.mjs (v0.3.5).
// The page list below is the single list of pages: validate.mjs fails on an index.md that is not in it.
// The domain comes from the CNAME file: canonical links, og:url, sitemap.xml and robots.txt are built from it.
//   node website/admin/build.mjs           write
//   node website/admin/build.mjs --check   exit 1 if any generated file is out of date (used by validate.mjs)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT    = join(dirname(fileURLToPath(import.meta.url)), '..');           // website/
const CHECK   = process.argv.includes('--check');
// CI owns the version: it is stamped in when the site is deployed (SITE_VERSION). The pages committed
// to the repository carry a placeholder, so that a version change never makes them out of date.
const VERSION = process.env.SITE_VERSION || 'dev';
const REPO    = 'https://github.com/VoiceDebrief/VoiceDebrief__App__iOS';
const SITE    = 'https://' + readFileSync(join(ROOT, 'CNAME'), 'utf8').trim();   // the CNAME file owns the domain
const pageUrl = (p) => `${SITE}/${p.path ? p.path + '/' : ''}index.html`;

const PAGES = [
  { path: '',         nav: 'Home',     title: 'VoiceDebrief for iPhone and iPad: transcript and debrief on the device',
    description: 'A native iPhone and iPad app that turns a voice note into a transcript and a debrief with Apple\'s on-device models, kept in an encrypted vault the user owns. In development: what is built and what is not.' },
  { path: 'built',    nav: 'Built',    title: 'What is built in VoiceDebrief for iOS',
    description: 'The reality file: what exists in the repository today, how it is tested, and what is not built yet. If it is not listed here, it does not exist.' },
  { path: 'architecture', nav: 'How it works', title: 'How VoiceDebrief for iOS works: the architecture in four drawings',
    description: 'The parts of the app, the life of a recording, a vault from the inside, lanes, the four keys and two devices, with what is seen working, what is unconfirmed and what is decided but not built.' },
  { path: 'conductors', nav: null, title: 'Receiving VoiceDebrief notes: how to become a recipient',
    description: 'For a person or an agent session that wants to receive voice notes from the app: make an inbox (a key pair, a vault, a lane), hand out its QR code or link, and open what arrives.' },
  { path: 'design',   nav: 'Design',   title: 'The VoiceDebrief iOS design: a recorder that does not lose things',
    description: 'What the app should look like and how it should behave: the three jobs, the decisions, the screens and three builds, agreed between a product agent and a design agent.' },
  { path: 'plan',     nav: 'Plan',     title: 'The VoiceDebrief iOS plan',
    description: 'The implementation plan: the pipeline on Apple\'s models, the passkey account, the vault, the identity, the repository and CI, milestones and risks.' },
  { path: 'articles', nav: 'Articles', title: 'Articles on VoiceDebrief for iOS',
    description: 'Ideas, positions and briefs for the project: the lab, two decision engines, a harness inside the app, the vault as a version-controlled store, voice everywhere, synthetic users.' },
  { path: 'articles/the-lab', nav: null, title: 'The lab: finding out what the Apple platform can do',
    description: 'A brief: use the app as a laboratory for on-device models, tool calls, vaults and interfaces, before deciding what the product is. Ten experiments.' },
  { path: 'articles/two-decision-engines', nav: null, title: 'Two decision engines: the code and the model',
    description: 'A position: the code owns the states and the model is asked one question at a time, through function calls, with no long history.' },
  { path: 'articles/a-harness-inside-the-app', nav: null, title: 'A harness inside the app',
    description: 'A brief: give the model its network, files, keys and vaults through separate doors, in the shape of SHarness, and draw what passes through them.' },
  { path: 'articles/the-vault-is-a-version-controlled-store', nav: null, title: 'The vault is a version-controlled store',
    description: 'A position and a brief: a vault needs no server to exist; a server is a remote; several vaults and lanes; a file system, vault apps and graphs.' },
  { path: 'articles/where-each-key-lives', nav: null, title: 'Where each key lives',
    description: 'A position and a brief: vault keys and the user key travel through iCloud Keychain, the device key never leaves the device, the person vouches for the device, and optionally a delegation from pki.sgit.ai.' },
  { path: 'articles/voice-everywhere', nav: null, title: 'Voice everywhere, and a recording that is never lost',
    description: 'An idea: voice as the way in from every screen, why the live words matter, and more than one interface to try.' },
  { path: 'articles/synthetic-users', nav: null, title: 'Synthetic users for an app its builder cannot see',
    description: 'A brief: invented users walking screenshots of every screen to find where a real one would get lost.' },
  { path: 'sgit-app/design', nav: null, title: 'The sgit app for iPhone, iPad and Mac: design for milestone one',
    description: 'sgit as a native app: put photos, videos and large files in an encrypted vault, browse them, share the vault and read its history. The jobs, the decisions, the screens, the share mechanisms and the limits.' },
  { path: 'sgit-app/built', nav: null, title: 'What is built in the sgit app',
    description: 'The reality file for the sgit app: what exists, how it is tested, and what does not exist yet.' },
  { path: 'develop',  nav: 'Build',    title: 'Build, test and release VoiceDebrief for iOS',
    description: 'How the repository is laid out, how CI compiles and tests the app on a Mac, how the site is built, and how a release is made.' },
  { path: 'versions', nav: null,       title: 'VoiceDebrief for iOS release history',
    description: 'Every release of the VoiceDebrief iOS repository, with what changed.' },
];

// ---------------------------------------------------------------- markdown (the subset these pages use)
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const slug = (s) => s.toLowerCase().replace(/<[^>]+>/g, '').replace(/&[a-z]+;/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const CHIPS = { keep: 'holds', verified: 'verified', wrong: 'wrong', critical: 'critical', missing: 'missing', change: 'change',
                spec: 'specified', spike: 'spike', proposed: 'proposed', unverified: 'unverified', built: 'built' };

function linkHref(href) {
  if (/^[a-z]+:/i.test(href) || href.startsWith('#')) return href;
  return href.replace(/(^|\/)index\.md(#.*)?$/, (m, a, h) => `${a}index.html${h || ''}`);
}

function inline(src) {
  const codes = [];
  let s = src.replace(/`([^`]+)`/g, (m, c) => { codes.push(c); return `\u0000${codes.length - 1}\u0000`; });
  s = esc(s);
  s = s.replace(/\[\[([a-z]+)\]\]/g, (m, k) => CHIPS[k] ? `<span class="chip chip-${k}">${CHIPS[k]}</span>` : m);
  s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (m, alt, src) => `<img class="shot" src="${src}" alt="${alt}" loading="lazy">`);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, t, h) => `<a href="${linkHref(h.replace(/&amp;/g, '&')).replace(/&/g, '&amp;')}">${t}</a>`);
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^\w*])\*([^*\s][^*]*?)\*(?=[^\w*]|$)/g, '$1<em>$2</em>');
  s = s.replace(/&lt;kbd&gt;(.*?)&lt;\/kbd&gt;/g, '<kbd>$1</kbd>');
  s = s.replace(/ {2}$/, '<br>');
  return s.replace(/\u0000(\d+)\u0000/g, (m, i) => `<code>${esc(codes[+i])}</code>`);
}

function render(md) {
  const lines = md.replace(/\r/g, '').split('\n');
  const out = [];
  const ids = new Set();
  let i = 0;
  const isBlockStart = (l) => /^(#{1,6} |```|> ?|\s*([-*]|\d+\.) |\|)/.test(l) || /^(---|\*\*\*)\s*$/.test(l) || /^<!--/.test(l);
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    if (/^<!--.*-->\s*$/.test(l)) { i++; continue; }                                  // markers
    let m;
    if ((m = l.match(/^(#{1,6}) (.*)$/))) {
      const lvl = m[1].length, html = inline(m[2]);
      let id = slug(html) || 'section'; while (ids.has(id)) id += '-x'; ids.add(id);
      out.push(`<h${lvl} id="${id}">${html}</h${lvl}>`); i++; continue;
    }
    if (l.startsWith('```')) {
      const lang = l.slice(3).trim(); const buf = []; i++;
      while (i < lines.length && !lines[i].startsWith('```')) buf.push(lines[i++]);
      i++;
      out.push(`<pre${lang ? ` data-lang="${esc(lang)}"` : ''}><code>${esc(buf.join('\n'))}</code></pre>`); continue;
    }
    if (/^(---|\*\*\*)\s*$/.test(l)) { out.push('<hr>'); i++; continue; }
    if (/^> ?/.test(l)) {
      const buf = []; while (i < lines.length && /^> ?/.test(lines[i])) buf.push(lines[i++].replace(/^> ?/, ''));
      out.push(`<blockquote>${render(buf.join('\n'))}</blockquote>`); continue;
    }
    if (l.startsWith('|')) {
      const rows = []; while (i < lines.length && lines[i].startsWith('|')) rows.push(lines[i++]);
      const cells = (r) => r.trim().replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map(c => c.trim().replace(/\\\|/g, '|'));
      const head = cells(rows[0]); const body = rows.slice(2).map(cells);
      const th = head.map(c => `<th>${inline(c)}</th>`).join('');
      const tb = body.map(r => `<tr>${r.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('\n');
      out.push(`<div class="tablewrap"><table>\n<thead><tr>${th}</tr></thead>\n<tbody>\n${tb}\n</tbody></table></div>`); continue;
    }
    if ((m = l.match(/^(\s*)([-*]|\d+\.) /))) {
      const ordered = /\d/.test(m[2]); const indent = m[1].length; const items = [];
      while (i < lines.length) {
        const x = lines[i];
        const mm = x.match(/^(\s*)([-*]|\d+\.) (.*)$/);
        if (mm && mm[1].length === indent) { items.push([mm[3]]); i++; continue; }
        if (mm && mm[1].length > indent) { items[items.length - 1].push(x.slice(indent + 2)); i++; continue; }
        if (x.trim() && /^\s{2,}/.test(x) && !mm) { items[items.length - 1].push(x.trim()); i++; continue; }
        break;
      }
      const li = items.map(([first, ...rest]) => {
        const sub = rest.filter(r => /^\s*([-*]|\d+\.) /.test(r));
        const cont = rest.filter(r => !/^\s*([-*]|\d+\.) /.test(r));
        return `<li>${inline([first, ...cont].join(' '))}${sub.length ? render(sub.join('\n')) : ''}</li>`;
      }).join('\n');
      out.push(ordered ? `<ol>\n${li}\n</ol>` : `<ul>\n${li}\n</ul>`); continue;
    }
    const buf = [];
    while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) buf.push(lines[i++]);
    const para = buf.map(inline).join('\n');
    // a paragraph that is only a "Download ..." link is the page's button
    if (/^<a href="[^"]+">Download [^<]*<\/a>$/.test(para)) { out.push(`<p class="ctas" style="justify-content:flex-start">${para.replace('<a ', '<a class="cta1" ')}</p>`); continue; }
    out.push(`<p>${para}</p>`);
  }
  return out.join('\n');
}

// ---------------------------------------------------------------- page frame
function frame(page, body) {
  const depth = page.path ? page.path.split('/').length : 0;
  const up = depth ? '../'.repeat(depth) : '';
  const nav = PAGES.filter(p => p.nav && p.path).map(p =>
    `  <a class="nl${p.path === page.path || (page.path.startsWith(p.path + '/') && p.path) ? ' here' : ''}" href="${up}${p.path}/index.html">${p.nav}</a>`).join('\n');
  const crumb = page.path ? `<div class="crumb"><a href="${up}index.html">VoiceDebrief iOS</a> / ${esc(page.path.replace(/\//g, ' / '))}</div>\n` : '';
  return `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(page.title)}</title>
<meta name="description" content="${esc(page.description)}">
<link rel="canonical" href="${pageUrl(page)}">
<meta property="og:url" content="${pageUrl(page)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="VoiceDebrief for iOS">
<meta property="og:title" content="${esc(page.title)}">
<meta property="og:description" content="${esc(page.description)}">
<link rel="alternate" type="text/markdown" href="index.md" title="This page as markdown">
<link rel="icon" href="${up}assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="${up}assets/vd-tokens.css">
<link rel="stylesheet" href="${up}assets/site.css">
</head>
<body>

<nav class="site"><div class="row">
  <a class="brand" href="${up}index.html">Voice<em>Debrief</em> <span>iOS</span></a>
  <span class="beta" title="In development: there is nothing to install yet">IN DEVELOPMENT</span>
  <a class="parent" href="https://voicedebrief.ai" title="A VoiceDebrief product">&#8599; part of <b>voicedebrief.ai</b></a>
  <a class="ver" href="${up}versions/index.html" title="Release history">${esc(VERSION)}</a>
${nav}
  <a class="gh" href="${REPO}">&#9733; GitHub</a>
</div></nav>

<main class="doc">
${crumb}${body}
</main>

<footer class="site"><div class="cols">
  <div>
    <div class="brandline">Voice<em>Debrief</em> <span>iOS</span></div>
    <p>The VoiceDebrief transcript and debrief as a native iPhone and iPad app, on Apple's own models, with the results in a vault you own. In development: there is nothing to install yet. Content CC BY 4.0; code Apache 2.0.</p>
    <p class="partnote">This site is static and has no analytics.</p>
    <p class="verline">site ${esc(VERSION)} · <a href="index.md">this page as markdown</a> · <a href="${up}llms.txt">llms.txt</a></p>
  </div>
  <div>
    <h4>The app</h4>
    <a href="${up}built/index.html">What is built</a>
    <a href="${up}plan/index.html">The plan</a>
    <a href="${up}develop/index.html">Build and test</a>
    <a href="${up}versions/index.html">Release history</a>
    <a href="${REPO}">GitHub</a>
  </div>
  <div>
    <h4>VoiceDebrief</h4>
    <a href="https://voicedebrief.ai">voicedebrief.ai</a>
    <a href="https://meetscribe.chrome-extension.voicedebrief.ai">MeetScribe for Google Meet</a>
  </div>
  <div>
    <h4>Built on</h4>
    <a href="https://sgit.ai">sgit.ai</a>
    <a href="https://pki.sgit.ai">pki.sgit.ai</a>
    <a href="https://sgit.ai/security/index.html">The vault security model</a>
  </div>
</div></footer>
</body>
</html>
`;
}

// ---------------------------------------------------------------- run
let stale = [];
const put = (rel, content) => {
  const abs = join(ROOT, rel);
  const old = existsSync(abs) ? readFileSync(abs, 'utf8') : null;
  if (old === content) return;
  if (CHECK) stale.push(rel); else writeFileSync(abs, content);
};

for (const page of PAGES) {
  const mdRel = join(page.path, 'index.md');
  const md = readFileSync(join(ROOT, mdRel), 'utf8');
  put(join(page.path, 'index.html'), frame(page, render(md)));
}

put('sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
  PAGES.map(p => `  <url><loc>${pageUrl(p)}</loc></url>`).join('\n') + `\n</urlset>\n`);
put('robots.txt', `User-agent: *\nAllow: /\nSitemap: ${SITE}/sitemap.xml\n`);

if (CHECK) {
  if (stale.length) { console.error(`out of date, run node admin/build/build.mjs:\n  ${stale.join('\n  ')}`); process.exit(1); }
  console.log(`build check: ${PAGES.length} pages up to date`);
} else console.log(`built ${PAGES.length} pages, ${VERSION}`);
