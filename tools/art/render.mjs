// Renders the house drawings (art.mjs) to the files the apps and the site use.
// Usage: node tools/art/render.mjs   (needs Playwright's Chromium and ImageMagick's convert)
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { tiles, iconVoiceDebrief, iconSGit, infographics } from './art.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const root = resolve(dirname(new URL(import.meta.url).pathname), '../..');
const vdAssets = join(root, 'Apps/VoiceDebrief/Resources/Assets.xcassets');
const sgAssets = join(root, 'Apps/SGit/Resources/Assets.xcassets');
const site = join(root, 'website/assets/art');

// One per RootTab, plus diagnostics (inside Settings). Keep in step with Sources/UI/Design/Sections.swift.
const vdTiles = ['record', 'library', 'contacts', 'vaults', 'identity', 'credit', 'activity', 'lab', 'words', 'about', 'settings', 'diagnostics'];
const sgTiles = ['vaults', 'gallery', 'share', 'history', 'settings'];

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
async function png(svg, w, h, out) {
  await page.setViewportSize({ width: w, height: h });
  await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
  await page.locator('svg').screenshot({ path: out });
}

function imageset(catalogue, name, file, src) {
  const dir = join(catalogue, 'Art', `${name}.imageset`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  execFileSync('cp', [src, join(dir, file)]);
  writeFileSync(join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: file, idiom: 'universal' }], info: { author: 'xcode', version: 1 },
  }, null, 2) + '\n');
}

function folder(catalogue) {
  mkdirSync(join(catalogue, 'Art'), { recursive: true });
  writeFileSync(join(catalogue, 'Art', 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 }, properties: { 'provides-namespace': false } }, null, 2) + '\n');
}

mkdirSync(site, { recursive: true });
folder(vdAssets); folder(sgAssets);
const tmp = join(tmpdir(), 'art'); mkdirSync(tmp, { recursive: true });
const jpeg = (src, out) => execFileSync('convert', [src, '-strip', '-quality', '82', '-sampling-factor', '4:2:0', '-interlace', 'JPEG', out]);

for (const [app, list, catalogue, prefix] of [['vd', vdTiles, vdAssets, 'VDArt'], ['sg', sgTiles, sgAssets, 'SGArt']]) {
  for (const name of list) {
    const raw = join(tmp, `${app}-${name}.png`);
    await png(tiles[name](), 720, 540, raw);
    const file = `${prefix}-${name}.jpg`; // resource names must be unique across the repository
    const out = join(tmp, file);
    jpeg(raw, out);
    imageset(catalogue, `${prefix}-${name}`, file, out);
    execFileSync('cp', [out, join(site, `${app}-${name}.jpg`)]);
  }
}

for (const [svg, catalogue, siteName] of [[iconVoiceDebrief(), vdAssets, 'icon-voicedebrief'], [iconSGit(), sgAssets, 'icon-sgit']]) {
  const out = join(catalogue, 'AppIcon.appiconset', 'AppIcon.png');
  const raw = join(tmp, `${siteName}.png`);
  await png(svg, 1024, 1024, raw);
  execFileSync('convert', [raw, '-alpha', 'off', '-strip', out]);
  execFileSync('convert', [raw, '-resize', '256x256', '-strip', join(site, `${siteName}.png`)]);
  writeFileSync(join(site, `${siteName}.svg`), svg);
}
for (const [name, draw] of Object.entries(infographics)) {
  const svg = draw();
  writeFileSync(join(site, `info-${name}.svg`), svg);
  const m = svg.match(/width="(\d+)" height="(\d+)"/);
  const raw = join(tmp, `info-${name}.png`);
  await png(svg, +m[1], +m[2], raw);
  jpeg(raw, join(site, `info-${name}.jpg`)); // for places that cannot show SVG
}
await browser.close();
console.log('rendered');
