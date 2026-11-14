// The ideas tracker, generated. No dependencies, no network.
//   node website/admin/ideas.mjs           write
//   node website/admin/ideas.mjs --check   exit 1 if a generated file is out of date (run by validate.mjs)
//
// Reads every issue (issues/open, issues/done), every article (website/articles/*), both reality files
// (website/built, website/sgit-app/built) and the release history (website/versions/index.md), and writes:
//   website/ideas/ideas.json                      every idea, request and feature, with its status
//   website/ideas/index.md                        the same as a page (build.mjs makes its index.html)
//   Apps/VoiceDebrief/Resources/vd-ideas.json     a copy for the app's Ideas screen
//   Apps/VoiceDebrief/Resources/vd-versions.json  the release history, for the app's What is new screen
//
// A status is never guessed. It comes from these rules, in order, and each idea carries the sentence that
// decided it (`why`):
//   1. An issue may say `**Idea status:** <one of the five>` on a line of its own. That wins.
//   2. A row of a reality file: [[built]] is seen working (a run proved it); [[unverified]] is built,
//      untried; [[proposed]] is proposed.
//   3. An issue in issues/done: built, untried if its first lines say untried, not yet run or seen, or not
//      run on a device; otherwise seen working.
//   4. An issue in issues/open: built, untried if its first lines begin "Built" and say untried;
//      parked if its status line says blocked, the owner's decision, a question for the owner, with the
//      owner, later or to schedule; in progress if it has a summary line above its status, says partly or
//      nearly done or a first version, or a release names it; otherwise proposed.
//   5. An article: in progress if an issue it names is built or seen working, otherwise proposed.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SITE, '..');
const CHECK = process.argv.includes('--check');
const GITHUB = 'https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev';
const HOST = 'https://' + readFileSync(join(SITE, 'CNAME'), 'utf8').trim();

export const STATUSES = [
  { id: 'seen-working',  label: 'Seen working',   meaning: 'Built, and a run proved it: CI, a device or a server.' },
  { id: 'built-untried', label: 'Built, untried', meaning: 'In the app or the repository, but not yet proven by a run on a device.' },
  { id: 'in-progress',   label: 'In progress',    meaning: 'Begun: part of it is built or a release has touched it.' },
  { id: 'proposed',      label: 'Proposed',       meaning: 'Asked for or described; nothing of it is built.' },
  { id: 'parked',        label: 'Parked',         meaning: 'Waiting: on the owner, on Apple, or scheduled for later.' },
];
const IDS = STATUSES.map((s) => s.id);

// ------------------------------------------------------------------ text
const plain = (s) => s
  .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
  .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
  .replace(/\[\[([a-z]+)\]\]/g, '')
  .replace(/`([^`]*)`/g, '$1')
  .replace(/\*\*([^*]+)\*\*/g, '$1')
  .replace(/(^|\W)\*([^*\n]+)\*(?=\W|$)/g, '$1$2')
  .replace(/\s+/g, ' ')
  .trim();
const paragraphs = (md) => md.replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
const clip = (s, n) => (s.length <= n ? s : s.slice(0, s.lastIndexOf(' ', n)).replace(/[,;:]$/, '') + '...');

// ------------------------------------------------------------------ where an idea lives in the app
// A Swift name or a phrase in an idea's text, and the place a person finds it. Most specific first.
const PLACES = [
  [/\bCleanTextView\b|clean text/i, 'A note: Clean text'],
  [/\bSendBar\b|send bar/i, 'A note: the send bar'],
  [/\bPlayerSection\b|\bNotePlayer\b|a player/i, 'A note: the player'],
  [/\bNoteDetailView\b|note screen|\bon a note\b/i, 'Library, then a note'],
  [/\bLibraryView\b|\bNoteRow\b|Library tab|the library/i, 'Library tab'],
  [/\bRecordView\b|record screen|record control|\bWhereWorkHappens\b/i, 'Record tab'],
  [/\bBriefing\b|briefing/i, 'Record tab: the briefing card'],
  [/version badge|release notes/i, 'The version badge in the top bar'],
  [/\bCreditView\b|\bCreditLedger\b|balance|credit/i, 'The balance in the top bar'],
  [/\bVaultsView\b|\bVaultBook\b|Vaults tab/i, 'Vaults tab'],
  [/\bIdentityView\b|\bIdentityBook\b|identity/i, 'Settings: Identity'],
  [/\bRecipientsView\b|\bRecipientStore\b|recipient/i, 'Settings: Recipients'],
  [/\bLabView\b|\bLabModelDoor\b|\bthe Lab\b/, 'Settings: Experiments, the Lab'],
  [/\bGlossaryView\b|Your words/i, 'Settings: Experiments, Your words'],
  [/\bDiagnosticsView\b|Diagnostics/i, 'Settings: Diagnostics'],
  [/\bTrafficView\b/i, 'Settings: Every step the vault engine took'],
  [/\bStatusView\b|About screen/i, 'Settings: What this build does'],
  [/\bAutoSave\b/i, 'Settings: Save to a vault'],
  [/\bSettingsView\b/i, 'Settings tab'],
  [/screens\.yml|ScreensTests|synthetic users/i, 'The repository: pictures of every screen'],
  [/\bconductor\.py\b|tools\/conductor/i, 'The repository: tools/conductor'],
  [/\.github\/workflows|\bCI\b/i, 'The repository: CI'],
];
const SGIT_PLACES = [
  [/\bGalleryView\b|gallery/i, 'SGit Vaults: Gallery'],
  [/\bCreateVaultSheet\b|Create sheet/i, 'SGit Vaults: the Create sheet'],
  [/\bVaultView\b|folder/i, 'SGit Vaults: a vault'],
  [/\bHistory\b/i, 'SGit Vaults: History'],
  [/share/i, 'SGit Vaults: Share'],
  [/Settings/i, 'SGit Vaults: Settings'],
];
function placesOf(text, app) {
  const table = app === 'SGit Vaults' ? [...SGIT_PLACES] : PLACES;
  const found = [];
  for (const [re, place] of table) if (re.test(text) && !found.includes(place)) found.push(place);
  if (app === 'SGit Vaults' && !found.length) found.push('SGit Vaults');
  return found.slice(0, 3);
}

// ------------------------------------------------------------------ issue numbers named in a text
function issueNumbers(text) {
  const out = new Set();
  const add = (n) => out.add(String(n).padStart(3, '0'));
  for (const m of text.matchAll(/issues? (\d{3})((?:(?:,| and| to|, and) \d{3})*)/g)) {
    const nums = [m[1], ...[...m[2].matchAll(/\d{3}/g)].map((x) => x[0])];
    if (/ to /.test(m[0]) && nums.length === 2) for (let n = +nums[0]; n <= +nums[1]; n++) add(n);
    else nums.forEach(add);
  }
  for (const m of text.matchAll(/\((\d{3})\)/g)) add(m[1]);
  for (const m of text.matchAll(/issues\/(?:open|done)\/(\d{3})-/g)) add(m[1]);
  return out;
}

// ------------------------------------------------------------------ the release history
function readVersions() {
  const rows = [];
  for (const line of readFileSync(join(SITE, 'versions/index.md'), 'utf8').split('\n')) {
    const m = line.match(/^\|\s*(v\d+\.\d+\.\d+|next)\s*\|([^|]*)\|(.*)\|\s*$/);
    if (m) rows.push({ version: m[1], date: m[2].trim(), text: m[3].trim() });
  }
  const byVersion = new Map();
  for (const r of rows) {
    if (r.version === 'next') continue;
    if (!byVersion.has(r.version)) byVersion.set(r.version, { version: r.version, date: r.date, notes: [] });
    byVersion.get(r.version).notes.push(plain(r.text));
  }
  const versions = [...byVersion.values()].sort((a, b) => b.version.localeCompare(a.version, 'en', { numeric: true }));
  for (const v of versions) {
    const dir = join(SITE, 'versions', v.version);
    v.hasPage = existsSync(join(dir, 'index.md'));     // pages begin at v0.1.29; older versions are rows only
    v.url = v.hasPage ? `${HOST}/versions/${v.version}/index.html` : `${HOST}/versions/index.html`;
    v.pictures = existsSync(dir) ? readdirSync(dir).filter((f) => /\.(png|jpe?g)$/i.test(f)).length : 0;
  }
  // the issues each version names, oldest version first, so an issue's first version is first
  const issueVersions = new Map();
  for (const v of [...versions].reverse()) {
    v.issues = [...new Set(v.notes.flatMap((n) => [...issueNumbers(n)]))].sort();
    for (const n of v.issues) { if (!issueVersions.has(n)) issueVersions.set(n, []); issueVersions.get(n).push(v.version); }
  }
  // rows headed next: the notes of the build that carries them, which has no number yet in the repository
  const next = rows.filter((r) => r.version === 'next').map((r) => plain(r.text));
  return { versions, issueVersions, next };
}

// ------------------------------------------------------------------ the reality files
function readReality(path, app, sitePath) {
  const md = readFileSync(join(SITE, path), 'utf8');
  const out = [];
  let section = '';
  for (const line of md.split('\n')) {
    const h = line.match(/^## (.*)/); if (h) { section = h[1]; continue; }
    if (!line.startsWith('|') || /^\|\s*(What|---)/.test(line)) continue;
    const cells = line.replace(/^\||\|\s*$/g, '').split(/(?<!\\)\|/).map((c) => c.trim());
    if (cells.length < 2) continue;
    const word = (line.match(/\[\[(built|unverified|proposed)\]\]/) || [])[1];
    if (!word) continue;
    const title = plain(cells[0]);
    const status = word === 'built' ? 'seen-working' : word === 'unverified' ? 'built-untried' : 'proposed';
    const wordSaid = { built: 'built: in the repository and proven by a run', unverified: 'unverified: written, not yet proven by a run', proposed: 'proposed: does not exist' }[word];
    const isBuiltTable = /^Built/.test(section);
    const where = isBuiltTable ? plain(cells[1]) : '';
    const tested = isBuiltTable ? plain(cells[2] || '') : plain(cells[1] || '');
    out.push({
      id: `${app === 'SGit Vaults' ? 'sgit-' : ''}feature-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60)}`,
      kind: 'feature', app, title, status,
      why: `The reality file, ${section}: ${wordSaid}.`,
      summary: clip(where || tested, 400),
      detail: [where, tested].filter(Boolean).map((s) => clip(s, 900)),
      places: placesOf(cells.join(' '), app),
      issues: [...issueNumbers(line)].sort(),
      url: `${HOST}/${sitePath}/index.html`,
      source: 'The reality file',
    });
  }
  return out;
}

// ------------------------------------------------------------------ the issues
function readIssues(issueVersions, realityByIssue) {
  const out = [];
  for (const folder of ['open', 'done']) {
    for (const f of readdirSync(join(REPO, 'issues', folder)).filter((f) => /^\d{3}-.*\.md$/.test(f)).sort()) {
      const md = readFileSync(join(REPO, 'issues', folder, f), 'utf8');
      const number = f.slice(0, 3);
      const title = plain((md.match(/^# (?:\d{3}: )?(.*)$/m) || [, f])[1]);
      const paras = paragraphs(md.replace(/^# .*$/m, ''));
      const statusIdx = paras.findIndex((p) => /^\*\*Status:\*\*/.test(p));
      const statusLine = statusIdx >= 0 ? plain(paras[statusIdx]) : '';
      const summaryLine = statusIdx > 0 ? plain(paras.slice(0, statusIdx).join(' ')) : '';
      const head = `${summaryLine} ${statusLine}`;
      const [, explicit, explicitWhy] = md.match(/^\*\*Idea status:\*\*\s*([a-z-]+)\.?\s*(.*)$/m) || [];
      const versions = issueVersions.get(number) || [];
      const begun = paras.find((p, i) => i > statusIdx && (/^(\*\*)?(Built\b|Done:)/.test(p) || /\bDone in answer\b/.test(p)));
      const listed = realityByIssue.get(number) || [];
      const app = +number >= 100 ? 'SGit Vaults' : 'VoiceDebrief';
      let status, why;
      if (explicit && IDS.includes(explicit)) { status = explicit; why = `The issue's Idea status line${explicitWhy ? `: "${clip(plain(explicitWhy), 160)}"` : '.'}`; }
      else if (folder === 'done') {
        if (/untried|not yet (run|seen|tried)|not run on a device/i.test(head)) { status = 'built-untried'; why = `Done in the code, and the issue says: "${clip(head.trim(), 160)}"`; }
        else {
          status = 'seen-working';
          const said = summaryLine || (/^Status: open/.test(statusLine) ? '' : statusLine);
          why = said ? `Moved to done, and the issue says: "${clip(said, 160)}"` : 'Moved to issues/done, with no untried work said in it.';
        }
      } else if (/^Built\b/.test(summaryLine) && /untried/i.test(summaryLine)) {
        status = 'built-untried'; why = `The issue says: "${clip(summaryLine, 160)}"`;
      } else if (/blocked|owner's decision|question for the owner|with the owner|\blater\b|to schedule/i.test(statusLine)) {
        status = 'parked'; why = `The issue's status: "${clip(statusLine, 160)}"`;
      } else if (summaryLine || begun || listed.length || /partly done|nearly done|first version/i.test(statusLine) || versions.length) {
        status = 'in-progress';
        why = summaryLine ? `The issue says: "${clip(summaryLine, 160)}"`
          : begun ? `The issue says: "${clip(plain(begun), 160)}"`
          : listed.length ? `Open, and the reality file lists for it: ${listed.join('; ')}.`
          : versions.length ? `Open, and named by the release notes of ${versions.join(', ')}.`
          : `The issue's status: "${clip(statusLine, 160)}"`;
      } else { status = 'proposed'; why = `Open, with nothing built yet: "${clip(statusLine, 160)}"`; }

      const body = paras.filter((_, i) => i !== statusIdx && !(statusIdx > 0 && i < statusIdx)).filter((p) => !/^\*\*Idea status:/.test(p));
      const detail = body.slice(0, 8).map((p) => clip(plain(p.replace(/^#+ /, '')), 900)).filter(Boolean);
      const owner = (statusLine.match(/Owner: ([^.]*(?:\([^)]*\))?[^.]*)\./) || [])[1];
      const source = /voice note|voice memo/i.test(statusLine) ? "The owner's voice note"
        : /review round/i.test(statusLine) ? 'A review by synthetic users'
        : /owner/i.test(statusLine) ? 'The owner' : 'The project';
      out.push({
        id: `issue-${number}`, kind: 'issue', number, app, title, status, why,
        summary: clip(summaryLine || detail[0] || '', 400),
        detail,
        statusLine: clip(statusLine, 600),
        owner: owner ? plain(owner) : undefined,
        places: placesOf(md, app),
        versions,
        features: realityByIssue.get(number) || [],
        url: `${GITHUB}/issues/${folder}/${f}`,
        source,
      });
    }
  }
  return out;
}

// ------------------------------------------------------------------ the articles
function readArticles(issueStatus) {
  const dir = join(SITE, 'articles');
  const out = [];
  for (const d of readdirSync(dir).filter((d) => existsSync(join(dir, d, 'index.md'))).sort()) {
    const md = readFileSync(join(dir, d, 'index.md'), 'utf8');
    const title = plain((md.match(/^# (.*)$/m) || [, d])[1]);
    const paras = paragraphs(md.replace(/^# .*$/m, '')).filter((p) => !/^(>|!\[|\[!\[|#)/.test(p));
    const kindLine = paras[0] && /^(\*|\*\*Kind)/.test(paras[0]) ? plain(paras.shift()) : '';
    const issues = [...issueNumbers(md)].filter((n) => issueStatus.has(n)).sort();
    const builtOnes = issues.filter((n) => ['seen-working', 'built-untried', 'in-progress'].includes(issueStatus.get(n)));
    const status = builtOnes.length ? 'in-progress' : 'proposed';
    const why = builtOnes.length
      ? `An article; work it names has begun: issue ${builtOnes.join(', ')}.`
      : 'An article: a position or a brief. Nothing in it is built unless the reality file says so.';
    out.push({
      id: `article-${d}`, kind: 'article', app: 'Both', title, status, why,
      summary: clip(plain(paras[0] || ''), 400),
      detail: [kindLine, ...paras.slice(0, 6).map((p) => plain(p.replace(/^#+ /, '')))].filter(Boolean).map((p) => clip(p, 900)),
      places: [],
      issues,
      url: `${HOST}/articles/${d}/index.html`,
      source: kindLine ? clip(kindLine, 160) : 'An article',
    });
  }
  return out;
}

// ------------------------------------------------------------------ assemble
export function generate() {
  const { versions, issueVersions, next } = readVersions();
  const features = [
    ...readReality('built/index.md', 'VoiceDebrief', 'built'),
    ...readReality('sgit-app/built/index.md', 'SGit Vaults', 'sgit-app/built'),
  ];
  const realityByIssue = new Map();
  for (const f of features) for (const n of f.issues) { if (!realityByIssue.has(n)) realityByIssue.set(n, []); realityByIssue.get(n).push(f.title); }
  const issues = readIssues(issueVersions, realityByIssue);
  const issueStatus = new Map(issues.map((i) => [i.number, i.status]));
  const articles = readArticles(issueStatus);
  for (const f of features) f.versions = [...new Set(f.issues.flatMap((n) => issueVersions.get(n) || []))];
  const ideas = [...issues, ...articles, ...features];
  for (const i of ideas) if (!IDS.includes(i.status)) throw new Error(`${i.id}: unknown status ${i.status}`);
  const counts = Object.fromEntries(IDS.map((s) => [s, ideas.filter((i) => i.status === s).length]));
  const ideasJson = JSON.stringify({ about: 'Generated by website/admin/ideas.mjs from issues/, website/articles/, the reality files and the release history. Do not edit.', statuses: STATUSES, counts, ideas }, null, 1) + '\n';
  const versionsJson = JSON.stringify({ about: 'Generated by website/admin/ideas.mjs from website/versions/index.md. Do not edit. next holds the notes of a build that has no number yet: the running build, if its own version is not listed.', next, versions }, null, 1) + '\n';
  return { ideas, ideasJson, versionsJson, counts, versions };
}

function page({ ideas, counts }) {
  const label = Object.fromEntries(STATUSES.map((s) => [s.id, s.label]));
  const cell = (s) => s.replace(/\|/g, '\\|');
  const kinds = { issue: 'Issue', article: 'Article', feature: 'Feature' };
  const link = (i) => i.kind === 'issue' ? `[${i.number}](${i.url})`
    : i.kind === 'article' ? `[article](../articles/${i.id.replace('article-', '')}/index.md)`
    : `[reality file](../${i.app === 'SGit Vaults' ? 'sgit-app/built' : 'built'}/index.md)`;
  const parts = [`# Ideas and where they stand

Every idea and request for the two apps, from the [issues](${GITHUB.replace('/blob/dev', '/tree/dev')}/issues), the [articles](../articles/index.md) and the reality files ([VoiceDebrief](../built/index.md), [SGit Vaults](../sgit-app/built/index.md)), with its status. This page and the Ideas screen in the app are generated from those files by \`website/admin/ideas.mjs\`; nothing here is written by hand. The rules that decide a status are at the top of that script, and every idea in the app shows the sentence that decided its own. The machine-readable form is [ideas.json](ideas.json).

| Status | Meaning | How many |
|---|---|---|
${STATUSES.map((s) => `| ${s.label} | ${s.meaning} | ${counts[s.id]} |`).join('\n')}
`];
  for (const s of STATUSES) {
    const rows = ideas.filter((i) => i.status === s.id);
    if (!rows.length) continue;
    parts.push(`## ${s.label}

| What | Kind | App | Where in the app | Versions | Detail |
|---|---|---|---|---|---|
${rows.map((i) => `| ${cell(i.title)} | ${kinds[i.kind]} | ${i.app} | ${cell((i.places || []).join('; ')) || ' '} | ${(i.versions || []).map((v) => existsSync(join(SITE, 'versions', v, 'index.md')) ? `[${v}](../versions/${v}/index.md)` : v).join(' ') || ' '} | ${link(i)} |`).join('\n')}
`);
  }
  return parts.join('\n');
}

// ------------------------------------------------------------------ write or check
if (import.meta.url === `file://${process.argv[1]}`) {
  const g = generate();
  const files = [
    [join(SITE, 'ideas/ideas.json'), g.ideasJson],
    [join(SITE, 'ideas/index.md'), page(g)],
    [join(REPO, 'Apps/VoiceDebrief/Resources/vd-ideas.json'), g.ideasJson],
    [join(REPO, 'Apps/VoiceDebrief/Resources/vd-versions.json'), g.versionsJson],
  ];
  const stale = files.filter(([p, s]) => !existsSync(p) || readFileSync(p, 'utf8') !== s).map(([p]) => p.slice(REPO.length + 1));
  if (CHECK) {
    if (stale.length) { console.error(`ideas: out of date, run node website/admin/ideas.mjs:\n  ${stale.join('\n  ')}`); process.exit(1); }
    console.log(`ideas: ok (${g.ideas.length} ideas)`);
  } else {
    for (const [p, s] of files) { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s); }
    console.log(`ideas: ${g.ideas.length} ideas (${STATUSES.map((s) => `${g.counts[s.id]} ${s.label.toLowerCase()}`).join(', ')}); ${g.versions.length} versions`);
  }
}
