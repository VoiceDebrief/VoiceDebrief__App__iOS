// Run by CI (site.yml, increment-tag) when it gives a push to dev its version. Nobody runs it by hand.
//   node website/admin/release.mjs v0.1.28
// 1. The rows headed `next` in the release history become rows of this version.
// 2. This version gets its own page, versions/<version>/index.md, with what changed. The app's version
//    badge opens that page, so every released version has one, even when no notes were written.
// 3. The site is rebuilt, so the committed pages stay current.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const SITE = join(dirname(fileURLToPath(import.meta.url)), '..');
const version = process.argv[2];
if (!/^v\d+\.\d+\.\d+$/.test(version || '')) { console.error('usage: release.mjs vMAJOR.MINOR.PATCH'); process.exit(1); }

const date = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
const historyPath = join(SITE, 'versions/index.md');
const history = readFileSync(historyPath, 'utf8');
const lines = history.split('\n');
const notes = [];
const out = lines.map((line) => {
  // Lenient about spacing and an empty date column: a row is anything headed next.
  const m = line.match(/^\|\s*next\s*\|([^|]*)\|(.*)\|\s*$/);
  if (!m) return line;
  notes.push(m[2].trim());
  return `| ${version} | ${m[1].trim() || date} | ${m[2].trim()} |`;
});
if (notes.length) writeFileSync(historyPath, out.join('\n'));

const page = join(SITE, 'versions', version, 'index.md');
if (!existsSync(page)) {
  mkdirSync(dirname(page), { recursive: true });
  const body = notes.length
    // A note's relative links were written from versions/; this page is one folder deeper.
    ? notes.map((n) => n.trim().replace(/\]\((?![a-z]+:|#)([^)]+)\)/g, '](../$1)')).join('\n\n')
    : 'No notes were written for this version: it changed the repository (its pipeline, pages or tests) and not what the app does, or the change is described under the next version.';
  writeFileSync(page, `# What changed in ${version}

Released ${date}. Every push to the repository's \`dev\` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

${body}

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
`);
}
execFileSync(process.execPath, [join(SITE, 'admin/build.mjs')], { stdio: 'inherit' });
console.log(`${version}: ${notes.length} note(s) moved; page versions/${version}/`);
