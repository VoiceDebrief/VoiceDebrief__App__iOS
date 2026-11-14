// Release cards: ASCII boxes, one text file each, that travel with a release (the owner's request:
// "use ASCII art to provide the latest release notes"). A session writes one into website/versions/next/;
// release.mjs moves it into the version's folder and onto its page; the apps show it in What is new.
// The rules (checked by validate.mjs): plain printable ASCII, no tabs, at most 72 columns.
// Two placeholders are filled in at release, keeping a box's right edge where it was:
//   {{version}}  the version, e.g. v0.1.59        {{date}}  the release date, e.g. 14 November 2026
export const CARD_WIDTH = 72;

/** Fills a placeholder on each line; a line ending in a box edge keeps that edge in its column. */
export function fill(text, values) {
  return text.split('\n').map((line) => {
    let out = line;
    for (const [k, v] of Object.entries(values)) out = out.split(`{{${k}}}`).join(v);
    if (out === line || !/[|+]\s*$/.test(line)) return out;
    const edge = line.replace(/\s+$/, '').length - 1;           // column of the closing edge
    const body = out.replace(/\s+$/, '').slice(0, -1).replace(/\s+$/, '');
    return body.length < edge ? body + ' '.repeat(edge - body.length) + out.replace(/\s+$/, '').slice(-1) : out;
  }).join('\n');
}

/** Problems with a card's text: an empty list when it is fine. */
export function check(text) {
  const problems = [];
  text.split('\n').forEach((line, i) => {
    if (/[^\x20-\x7e]/.test(line)) problems.push(`line ${i + 1}: not plain printable ASCII`);
    if (line.length > CARD_WIDTH) problems.push(`line ${i + 1}: ${line.length} columns, more than ${CARD_WIDTH}`);
  });
  return problems;
}
