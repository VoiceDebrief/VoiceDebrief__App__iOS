// Writes the results page of Lab experiment L03, the voice game, from the logs dropped into
// website/lab/l03/runs/ (each the JSON the app shares from L03: Play, "Share the log as JSON").
//
//   node website/admin/l03.mjs           write website/lab/l03/index.md
//   node website/admin/l03.mjs --check   exit 1 if it is out of date (run through build.mjs --check)
//
// Only what the logs hold is reported. Tokens and energy in a log are estimates made by the app, and
// the page says so.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIR = join(ROOT, 'lab', 'l03');
const RUNS = join(DIR, 'runs');
const OUT = join(DIR, 'index.md');
const CHECK = process.argv.includes('--check');

const ms = (v) => (v == null || Number.isNaN(v) ? '-' : v >= 10000 ? `${(v / 1000).toFixed(1)} s` : `${Math.round(v)} ms`);
const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : '-');
const cell = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const totalMs = (e) => (e.appliedAt && e.endedAt ? Date.parse(e.appliedAt) - Date.parse(e.endedAt) : null);

/** The figures of one log, the same ones the app shows, worked out again from the entries. */
export function summarise(log) {
  const entries = log.entries ?? [];
  const by = (engine) => entries.filter((e) => e.engine === engine);
  const times = (list) => list.map(totalMs).filter((v) => v != null);
  const turns = entries.map((e) => e.model).filter(Boolean);
  const firstCalls = turns.map((t) => t.firstCallMs).filter((v) => v != null);
  const compared = entries.filter((e) => e.phrase && e.model && !e.model.error);
  const agreed = compared.filter((e) => e.modelCommand === e.phrase);
  const sources = {};
  for (const e of entries) {
    const t = totalMs(e);
    if (t == null) continue;
    (sources[e.source] ??= []).push(t);
  }
  return {
    commands: entries.length,
    phrases: { n: by('phrases').length, median: median(times(by('phrases'))), mean: mean(times(by('phrases'))) },
    model: { n: by('model').length, median: median(times(by('model'))), mean: mean(times(by('model'))) },
    requests: turns.length,
    firstCallMedian: median(firstCalls),
    noTool: turns.filter((t) => !t.tool && !t.error).length,
    errors: turns.filter((t) => t.error).map((t) => t.error.kind),
    prewarmed: turns.filter((t) => t.prewarmed).length,
    tokensMean: mean(turns.map((t) => (t.tokens ? t.tokens.instructions + t.tokens.prompt + t.tokens.tools : 0))),
    context: turns.find((t) => t.tokens?.context)?.tokens.context ?? log.device?.modelContextSize ?? null,
    energyMilliwattHours: turns.reduce((a, t) => a + (3 * ((t.totalMs ?? 0) / 1000)) / 3.6, 0),
    compared: compared.length,
    agreed: agreed.length,
    disagreements: compared.filter((e) => e.modelCommand !== e.phrase),
    refused: entries.filter((e) => e.modelRefusal),
    early: entries.filter((e) => e.early).length,
    sources: Object.fromEntries(Object.entries(sources).map(([k, v]) => [k, { n: v.length, median: median(v) }])),
    hints: (log.hints ?? []).length,
    found: [...new Set(entries.map((e) => e.outcome).filter((o) => /points for|hidden passage|for style/i.test(o ?? '')))].length,
  };
}

function runSection(name, log) {
  const s = summarise(log);
  const d = log.device ?? {};
  const lines = [
    `### ${name}`,
    '',
    `${cell(d.machine)}, ${cell(d.system)}, app ${cell(d.appVersion)}. Model: ${cell(d.modelStatus)}${d.modelContextSize ? `, context ${d.modelContextSize} tokens` : ''}.`,
    '',
    '| Measure | Value |',
    '|---|---|',
    `| Commands | ${s.commands} |`,
    `| Acted on by the phrases, median from the end of speaking | ${s.phrases.n}, ${ms(s.phrases.median)} |`,
    `| Acted on by the model, median from the end of speaking | ${s.model.n}, ${ms(s.model.median)} |`,
    `| Acted on before the words settled | ${s.early} |`,
    `| Model requests, median time to the tool call | ${s.requests}, ${ms(s.firstCallMedian)} |`,
    `| Requests on a prewarmed session | ${pct(s.prewarmed, s.requests)} |`,
    `| Requests with no tool called | ${s.noTool} |`,
    `| Requests that failed | ${s.errors.length ? `${s.errors.length} (${[...new Set(s.errors)].join(', ')})` : '0'} |`,
    `| Tokens a request, mean (estimated by the app) | ${s.tokensMean == null ? '-' : Math.round(s.tokensMean)}${s.context ? ` of ${s.context}` : ''} |`,
    `| Energy on the model (estimated, 3 W assumed) | ${s.energyMilliwattHours.toFixed(2)} mWh |`,
    `| Where both engines answered, they agreed | ${s.agreed} of ${s.compared} (${pct(s.agreed, s.compared)}) |`,
    `| Model calls refused by the code | ${s.refused.length} |`,
    `| Clues asked of the model | ${s.hints} |`,
  ];
  const src = Object.entries(s.sources);
  if (src.length) {
    lines.push('', '| Source | Commands timed | Median from the end of speaking |', '|---|---|---|');
    for (const [k, v] of src) lines.push(`| ${cell(k)} | ${v.n} | ${ms(v.median)} |`);
  }
  if (s.disagreements.length) {
    lines.push('', 'Where the phrases and the model disagreed:', '', '| Words | Phrases | Model | Model time |', '|---|---|---|---|');
    for (const e of s.disagreements.slice(0, 20)) {
      lines.push(`| ${cell(e.words)} | ${cell(e.phrase)} | ${cell(e.modelCommand ?? e.modelRefusal ?? 'no tool')} | ${ms(e.model?.firstCallMs ?? e.model?.totalMs)} |`);
    }
  }
  return lines.join('\n');
}

export function page(runs) {
  const head = [
    '# L03: the voice game, results',
    '',
    '*Generated by `website/admin/l03.mjs` from the logs in `runs/`. Do not edit by hand.*',
    '',
    'Lab experiment L03 ([issue 300](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/issues/open/300-the-voice-game.md)) is a small game played by voice, in which the fixed phrases (code) and Apple\'s on-device model (offered only the tools that make sense at that moment) turn a sentence into a move. Every command is timed from the end of speaking to the move. This page reports the logs the app exports.',
    '',
    '## Adding a run',
    '',
    '1. In the app: Settings, Lab, L03: Play. Play, then Share the log as JSON.',
    '2. Save the file as `website/lab/l03/runs/<date>-<device>.json` (for example `2026-11-15-iphone.json`).',
    '3. Run `node website/admin/l03.mjs` (or `node website/admin/build.mjs`) and commit the page with the log.',
    '',
    'A log holds every sentence word for word. Those are game commands, but read it before committing: what is in `runs/` is published.',
    '',
    '## How to read it',
    '',
    '- **From the end of speaking**: from the last change to the live words (spoken), the end of the voice player\'s speech (player) or the press of return (typed), to the new state. Below zero means acted on before the voice player finished.',
    '- **Tokens and energy are estimates** made by the app: four characters a token, and the model\'s time at an assumed 3 W. Not measurements.',
    '- **Agreed**: where the phrases found a command and the model was asked too, whether the model proposed the same command.',
    '',
  ];
  if (!runs.length) {
    return [...head, '## Runs', '', 'No run yet: the game has not been played on a device and no log has been added. Until one is, nothing is known about how fast or how right the model is here.', ''].join('\n');
  }
  const overview = ['## Runs', '', '| Run | Commands | Phrases, median | Model, median | Model to tool call, median | Agreed |', '|---|---|---|---|---|---|'];
  for (const { name, log } of runs) {
    const s = summarise(log);
    overview.push(`| ${cell(name)} | ${s.commands} | ${ms(s.phrases.median)} | ${ms(s.model.median)} | ${ms(s.firstCallMedian)} | ${pct(s.agreed, s.compared)} |`);
  }
  return [...head, ...overview, '', ...runs.map(({ name, log }) => runSection(name, log) + '\n')].join('\n');
}

function readRuns() {
  if (!existsSync(RUNS)) return [];
  return readdirSync(RUNS)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => {
      const log = JSON.parse(readFileSync(join(RUNS, f), 'utf8'));
      if (log.experiment !== 'L03') throw new Error(`${f}: not an L03 log`);
      return { name: f.replace(/\.json$/, ''), log };
    });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const text = page(readRuns());
  if (CHECK) {
    const now = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
    if (now !== text) {
      console.error('l03: out of date, run node website/admin/l03.mjs:\n  website/lab/l03/index.md');
      process.exit(1);
    }
  } else {
    mkdirSync(DIR, { recursive: true });
    writeFileSync(OUT, text);
  }
}
