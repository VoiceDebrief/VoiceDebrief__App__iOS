// The house drawings of VoiceDebrief and SGit Vaults, as code: one function per picture, each
// returning an SVG. render.mjs turns them into the JPEG and PNG files the apps and the site use.
// Style (website/design/identity): a navy night card, a soft glow of the section's colour, flat
// rounded shapes, off-white highlights, no words in any picture.

export const C = {
  navy: '#0B1B2B', navy2: '#12283C', navy3: '#1B3A55', ink: '#F2F6FA', mute: '#A9BDD2',
  green: '#0E9E72', greenHi: '#12C08A', mint: '#9FD8C4', amber: '#F0B429', red: '#E5484D',
  indigo: '#4F5BD5', indigoHi: '#7C86F0',
};

// One colour per section, shared with the Swift code (Sources/UI/Design/Sections.swift).
export const T = {
  record: '#0E9E72', library: '#2F80ED', vaults: '#4F5BD5', recipients: '#E5577E', identity: '#8E5CF7',
  credit: '#D4A12A', lab: '#13A8C8', words: '#2BB39A', diagnostics: '#7B8DA3', status: '#12C08A',
  settings: '#8A9BB0', gallery: '#E07A3F', share: '#E5577E', history: '#13A8C8',
};

// A deterministic sequence, so a picture is the same every time it is drawn.
function seq(n, seed = 7) {
  const out = []; let s = seed;
  for (let i = 0; i < n; i++) { s = (s * 9301 + 49297) % 233280; out.push(s / 233280); }
  return out;
}

function frame(w, h, accent, body, { glowX = 0.5, glowY = 0.46 } = {}) {
  const dots = [];
  for (let x = 24; x < w; x += 32) for (let y = 24; y < h; y += 32) dots.push(`<circle cx="${x}" cy="${y}" r="1.3"/>`);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
<defs>
  <radialGradient id="glow" cx="${glowX}" cy="${glowY}" r="0.62">
    <stop offset="0" stop-color="${accent}" stop-opacity="0.55"/>
    <stop offset="0.55" stop-color="${accent}" stop-opacity="0.12"/>
    <stop offset="1" stop-color="${accent}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="acc" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="${lighten(accent, 0.25)}"/><stop offset="1" stop-color="${accent}"/>
  </linearGradient>
  <linearGradient id="card" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4ECF4"/>
  </linearGradient>
  <linearGradient id="deep" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${C.navy3}"/><stop offset="1" stop-color="${C.navy2}"/>
  </linearGradient>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="0.35"/>
  </filter>
</defs>
<rect width="${w}" height="${h}" fill="${C.navy}"/>
<rect width="${w}" height="${h}" fill="url(#glow)"/>
<g fill="#FFFFFF" fill-opacity="0.05">${dots.join('')}</g>
<ellipse cx="${w / 2}" cy="${h * 0.84}" rx="${w * 0.3}" ry="${h * 0.035}" fill="#000" fill-opacity="0.28"/>
${body}
</svg>`;
}

export function lighten(hex, t) {
  const n = parseInt(hex.slice(1), 16);
  const c = [n >> 16, (n >> 8) & 255, n & 255].map(v => Math.round(v + (255 - v) * t));
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
}

const lines = (x, y, w, n, gap, color, op = 1, h = 10) =>
  Array.from({ length: n }, (_, i) =>
    `<rect x="${x}" y="${y + i * gap}" width="${i === n - 1 ? w * 0.6 : w}" height="${h}" rx="${h / 2}" fill="${color}" fill-opacity="${op}"/>`).join('');

const bars = (x, cy, w, maxH, n, color, seed = 3, bw = 0) => {
  const r = seq(n, seed); const step = w / n; const b = bw || step * 0.55;
  return r.map((v, i) => {
    const h = maxH * (0.25 + 0.75 * Math.sin(Math.PI * (i + 0.5) / n) * (0.55 + 0.45 * v));
    return `<rect x="${x + i * step}" y="${cy - h / 2}" width="${b}" height="${h}" rx="${b / 2}" fill="${color}"/>`;
  }).join('');
};

const W = 720, H = 540;

export const tiles = {
  record: () => frame(W, H, T.record, `
    <circle cx="360" cy="250" r="168" fill="none" stroke="${C.mint}" stroke-opacity="0.12" stroke-width="2"/>
    <circle cx="360" cy="250" r="134" fill="none" stroke="${C.mint}" stroke-opacity="0.22" stroke-width="2"/>
    ${bars(70, 250, 170, 150, 9, C.mint, 5)}
    ${bars(490, 250, 170, 150, 9, C.mint, 11)}
    <g filter="url(#soft)"><circle cx="360" cy="250" r="96" fill="url(#acc)"/></g>
    <circle cx="360" cy="250" r="96" fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="3"/>
    <rect x="338" y="196" width="44" height="76" rx="22" fill="#FFFFFF"/>
    <path d="M318 252 a42 42 0 0 0 84 0" fill="none" stroke="#FFFFFF" stroke-width="9" stroke-linecap="round"/>
    <rect x="355" y="294" width="10" height="20" rx="4" fill="#FFFFFF"/>`),

  library: () => frame(W, H, T.library, [-14, -4, 6].map((rot, i) => `
    <g transform="rotate(${rot} 360 270)" filter="url(#soft)">
      <rect x="${220 + i * 6}" y="${120 + i * 26}" width="280" height="200" rx="22" fill="url(#card)"/>
      <rect x="${244 + i * 6}" y="${144 + i * 26}" width="44" height="44" rx="12" fill="${T.library}"/>
      ${bars(252 + i * 6, 166 + i * 26, 30, 26, 5, '#FFFFFF', 2 + i, 3.5)}
      ${lines(304 + i * 6, 150 + i * 26, 172, 2, 20, C.navy, 0.75)}
      ${lines(244 + i * 6, 214 + i * 26, 232, 3, 24, C.navy, 0.18)}
    </g>`).join('')),

  vaults: () => frame(W, H, T.vaults, `
    <g filter="url(#soft)">
      <rect x="200" y="96" width="320" height="320" rx="44" fill="url(#deep)" stroke="${C.indigoHi}" stroke-opacity="0.5" stroke-width="3"/>
    </g>
    <circle cx="360" cy="256" r="116" fill="url(#acc)"/>
    <circle cx="360" cy="256" r="116" fill="none" stroke="#FFFFFF" stroke-opacity="0.3" stroke-width="3"/>
    ${Array.from({ length: 8 }, (_, i) => { const a = i * Math.PI / 4; return `<circle cx="${360 + 98 * Math.cos(a)}" cy="${256 + 98 * Math.sin(a)}" r="7" fill="#FFFFFF" fill-opacity="0.85"/>`; }).join('')}
    <circle cx="360" cy="256" r="52" fill="${C.navy}" fill-opacity="0.35" stroke="#FFFFFF" stroke-width="6"/>
    ${[0, 60, 120].map(a => `<rect x="354" y="204" width="12" height="104" rx="6" fill="#FFFFFF" transform="rotate(${a} 360 256)"/>`).join('')}
    <circle cx="360" cy="256" r="16" fill="${C.indigo}" stroke="#FFFFFF" stroke-width="5"/>
    <g transform="rotate(-8 590 380)" filter="url(#soft)">
      <rect x="528" y="330" width="130" height="94" rx="16" fill="url(#card)"/>
      <rect x="544" y="346" width="28" height="28" rx="8" fill="${C.green}"/>
      ${lines(582, 350, 60, 2, 16, C.navy, 0.6, 8)}${lines(544, 390, 98, 2, 16, C.navy, 0.18, 8)}
    </g>`),

  recipients: () => frame(W, H, T.recipients, `
    <path d="M150 360 C 260 200, 460 420, 590 170" fill="none" stroke="${C.mint}" stroke-opacity="0.45" stroke-width="4" stroke-dasharray="4 14" stroke-linecap="round"/>
    ${[[150, 360], [590, 170], [470, 395]].map(([x, y], i) => `
      <g filter="url(#soft)"><circle cx="${x}" cy="${y}" r="${i === 2 ? 40 : 52}" fill="url(#deep)" stroke="${lighten(T.recipients, 0.3)}" stroke-width="3"/></g>
      <circle cx="${x}" cy="${y - (i === 2 ? 8 : 11)}" r="${i === 2 ? 11 : 15}" fill="#FFFFFF"/>
      <path d="M${x - (i === 2 ? 20 : 27)} ${y + (i === 2 ? 22 : 30)} a${i === 2 ? 20 : 27} ${i === 2 ? 17 : 23} 0 0 1 ${i === 2 ? 40 : 54} 0" fill="#FFFFFF"/>`).join('')}
    <g transform="translate(360 250) rotate(-18)" filter="url(#soft)">
      <path d="M-110 10 L110 -70 L40 80 L10 30 Z" fill="url(#acc)"/>
      <path d="M-110 10 L10 30 L110 -70 Z" fill="#FFFFFF"/>
      <path d="M10 30 L40 80 L30 40 Z" fill="${lighten(T.recipients, 0.45)}"/>
    </g>`),

  identity: () => frame(W, H, T.identity, `
    <g filter="url(#soft)">
      <path d="M360 96 L500 150 V262 C500 350 440 404 360 438 C280 404 220 350 220 262 V150 Z" fill="url(#deep)" stroke="${lighten(T.identity, 0.35)}" stroke-width="3"/>
    </g>
    <path d="M360 128 L472 172 V262 C472 334 424 378 360 406 C296 378 248 334 248 262 V172 Z" fill="url(#acc)"/>
    <g transform="rotate(-35 360 270)">
      <circle cx="360" cy="214" r="46" fill="none" stroke="#FFFFFF" stroke-width="18"/>
      <rect x="351" y="256" width="18" height="120" rx="6" fill="#FFFFFF"/>
      <rect x="369" y="320" width="30" height="16" rx="5" fill="#FFFFFF"/>
      <rect x="369" y="352" width="22" height="16" rx="5" fill="#FFFFFF"/>
    </g>
    ${[[150, 170], [580, 150], [600, 340], [130, 360]].map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${6 + i % 2 * 4}" fill="${C.mint}" fill-opacity="0.5"/>`).join('')}`),

  credit: () => frame(W, H, T.credit, `
    ${[0, 1, 2, 3, 4].map(i => `<g filter="url(#soft)"><ellipse cx="270" cy="${380 - i * 34}" rx="92" ry="30" fill="${lighten(T.credit, 0.1)}"/>
      <rect x="178" y="${350 - i * 34}" width="184" height="30" fill="${T.credit}"/>
      <ellipse cx="270" cy="${350 - i * 34}" rx="92" ry="30" fill="${lighten(T.credit, 0.35)}"/>
      <ellipse cx="270" cy="${350 - i * 34}" rx="58" ry="17" fill="none" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="4"/></g>`).join('')}
    <g filter="url(#soft)"><rect x="400" y="150" width="200" height="230" rx="28" fill="url(#deep)" stroke="${lighten(T.credit, 0.3)}" stroke-opacity="0.6" stroke-width="3"/></g>
    <path d="M440 290 A60 60 0 0 1 560 290" fill="none" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="16" stroke-linecap="round"/>
    <path d="M440 290 A60 60 0 0 1 530 238" fill="none" stroke="${T.credit}" stroke-width="16" stroke-linecap="round"/>
    <line x1="500" y1="290" x2="528" y2="246" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round"/>
    <circle cx="500" cy="290" r="10" fill="#FFFFFF"/>
    ${lines(436, 326, 128, 2, 20, '#FFFFFF', 0.35, 8)}`),

  lab: () => frame(W, H, T.lab, `
    <g filter="url(#soft)">
      <path d="M318 120 H402 V210 L478 356 C490 382 474 410 444 410 H276 C246 410 230 382 242 356 L318 210 Z" fill="url(#deep)" stroke="#FFFFFF" stroke-opacity="0.65" stroke-width="5" stroke-linejoin="round"/>
    </g>
    <path d="M286 300 H434 L470 362 C478 380 468 396 448 396 H272 C252 396 242 380 250 362 Z" fill="url(#acc)"/>
    <rect x="304" y="104" width="112" height="22" rx="11" fill="#FFFFFF"/>
    ${[[330, 340, 10], [384, 360, 14], [360, 322, 7], [410, 330, 6], [348, 270, 8], [372, 236, 5]].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#FFFFFF" fill-opacity="0.8"/>`).join('')}
    ${[[540, 170, 30], [180, 210, 20], [575, 300, 14]].map(([x, y, s]) => `<path d="M${x} ${y - s} Q${x} ${y} ${x + s} ${y} Q${x} ${y} ${x} ${y + s} Q${x} ${y} ${x - s} ${y} Q${x} ${y} ${x} ${y - s} Z" fill="${C.mint}"/>`).join('')}`),

  words: () => frame(W, H, T.words, `
    <g filter="url(#soft)">
      <path d="M180 140 Q270 116 360 140 V420 Q270 396 180 420 Z" fill="url(#card)"/>
      <path d="M540 140 Q450 116 360 140 V420 Q450 396 540 420 Z" fill="#DCE6EF"/>
    </g>
    ${lines(208, 172, 124, 6, 34, C.navy, 0.2)}
    ${lines(388, 172, 124, 6, 34, C.navy, 0.2)}
    <rect x="382" y="234" width="136" height="24" rx="8" fill="${T.words}" fill-opacity="0.85"/>
    <g filter="url(#soft)" transform="translate(470 92)">
      <path d="M0 0 H150 a24 24 0 0 1 24 24 V84 a24 24 0 0 1 -24 24 H54 L22 134 V108 H0 a24 24 0 0 1 -24 -24 V24 A24 24 0 0 1 0 0 Z" fill="url(#acc)"/>
      ${bars(10, 54, 140, 54, 8, '#FFFFFF', 9)}
    </g>`),

  diagnostics: () => frame(W, H, T.diagnostics, `
    <g filter="url(#soft)"><rect x="150" y="120" width="420" height="270" rx="30" fill="url(#deep)" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="3"/></g>
    ${[0, 1, 2, 3].map(i => `<line x1="180" x2="540" y1="${170 + i * 56}" y2="${170 + i * 56}" stroke="#FFFFFF" stroke-opacity="0.07" stroke-width="2"/>`).join('')}
    <polyline points="180,280 250,280 280,220 320,340 360,180 400,300 430,262 470,262 500,240 540,240" fill="none" stroke="${C.greenHi}" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"/>
    <circle cx="540" cy="240" r="12" fill="${C.greenHi}"/>
    <circle cx="540" cy="240" r="24" fill="${C.greenHi}" fill-opacity="0.25"/>
    ${[[200, 430, C.greenHi], [260, 430, C.greenHi], [320, 430, C.amber]].map(([x, y, c]) => `<rect x="${x - 22}" y="${y - 8}" width="44" height="16" rx="8" fill="${c}"/>`).join('')}`),

  status: () => frame(W, H, T.status, `
    <g filter="url(#soft)"><rect x="220" y="96" width="280" height="340" rx="30" fill="url(#card)"/></g>
    <rect x="300" y="80" width="120" height="36" rx="14" fill="${C.navy3}"/>
    ${[0, 1, 2, 3].map(i => `
      <circle cx="270" cy="${170 + i * 66}" r="20" fill="${i < 3 ? T.status : 'none'}" stroke="${i < 3 ? T.status : C.navy}" stroke-opacity="${i < 3 ? 1 : 0.3}" stroke-width="4"/>
      ${i < 3 ? `<path d="M260 ${170 + i * 66} l7 7 l13 -14" fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>` : ''}
      ${lines(306, 158 + i * 66, 160, 2, 16, C.navy, i < 3 ? 0.55 : 0.2, 8)}`).join('')}`),

  settings: () => frame(W, H, T.settings, `
    <g filter="url(#soft)" transform="translate(300 250)">
      ${Array.from({ length: 8 }, (_, i) => `<rect x="-18" y="-128" width="36" height="52" rx="10" fill="${lighten(T.settings, 0.2)}" transform="rotate(${i * 45})"/>`).join('')}
      <circle r="100" fill="url(#acc)"/>
      <circle r="42" fill="${C.navy}" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="6"/>
    </g>
    <g filter="url(#soft)"><rect x="440" y="250" width="180" height="170" rx="26" fill="url(#deep)" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="3"/></g>
    ${[0, 1, 2].map(i => `<rect x="466" y="${288 + i * 46}" width="128" height="8" rx="4" fill="#FFFFFF" fill-opacity="0.25"/>
      <circle cx="${490 + [60, 20, 90][i]}" cy="${292 + i * 46}" r="13" fill="${i === 0 ? C.greenHi : '#FFFFFF'}"/>`).join('')}`),

  gallery: () => frame(W, H, T.gallery, [[-10, 180, 130], [4, 300, 110], [14, 400, 160]].map(([rot, x, y], i) => `
    <g transform="rotate(${rot} ${x + 100} ${y + 100})" filter="url(#soft)">
      <rect x="${x}" y="${y}" width="200" height="200" rx="18" fill="url(#card)"/>
      <rect x="${x + 14}" y="${y + 14}" width="172" height="136" rx="10" fill="${[C.navy3, T.gallery, C.green][i]}"/>
      <circle cx="${x + 140}" cy="${y + 52}" r="16" fill="#FFFFFF" fill-opacity="0.85"/>
      <path d="M${x + 14} ${y + 150} L${x + 70} ${y + 86} L${x + 110} ${y + 124} L${x + 136} ${y + 100} L${x + 186} ${y + 150} Z" fill="#FFFFFF" fill-opacity="0.55"/>
    </g>`).join('')),

  share: () => frame(W, H, T.share, `
    <g filter="url(#soft)"><rect x="140" y="170" width="180" height="200" rx="30" fill="url(#deep)" stroke="${C.indigoHi}" stroke-opacity="0.6" stroke-width="3"/></g>
    <circle cx="230" cy="262" r="48" fill="${C.indigo}"/>
    <rect x="218" y="250" width="24" height="30" rx="6" fill="#FFFFFF"/>
    <path d="M220 252 v-10 a10 10 0 0 1 20 0 v10" fill="none" stroke="#FFFFFF" stroke-width="6"/>
    <path d="M330 270 C 400 200, 450 200, 500 250" fill="none" stroke="${C.mint}" stroke-width="5" stroke-dasharray="4 14" stroke-linecap="round"/>
    <g filter="url(#soft)" transform="translate(520 270)">
      <circle r="70" fill="url(#acc)"/>
      <g fill="none" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round">
        <path d="M-10 12 l-14 14 a18 18 0 0 1 -26 -26 l20 -20 a18 18 0 0 1 26 0"/>
        <path d="M10 -12 l14 -14 a18 18 0 0 1 26 26 l-20 20 a18 18 0 0 1 -26 0"/>
      </g>
    </g>`),

  history: () => frame(W, H, T.history, `
    <line x1="260" y1="110" x2="260" y2="430" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="10" stroke-linecap="round"/>
    <path d="M260 330 C 260 270, 400 290, 400 220 V150" fill="none" stroke="${C.greenHi}" stroke-width="10" stroke-linecap="round"/>
    ${[130, 210, 290, 370, 430].map((y, i) => `<circle cx="260" cy="${y}" r="${i === 0 ? 22 : 17}" fill="${C.navy}" stroke="#FFFFFF" stroke-width="8"/>`).join('')}
    ${[150, 220].map(y => `<circle cx="400" cy="${y}" r="17" fill="${C.navy}" stroke="${C.greenHi}" stroke-width="8"/>`).join('')}
    ${[130, 210, 290, 370].map((y, i) => `<g filter="url(#soft)"><rect x="${i < 2 ? 440 : 300}" y="${y - 22}" width="${i < 2 ? 150 : 170}" height="44" rx="14" fill="url(#deep)" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="2"/></g>
      ${lines((i < 2 ? 440 : 300) + 18, y - 5, i < 2 ? 100 : 120, 1, 0, '#FFFFFF', 0.45, 10)}`).join('')}`),
};

// The marks: VoiceDebrief is a voice (bars) becoming a note (lines); SGit Vaults is a vault whose
// door is a history (a commit graph). Both on the same navy gradient, the family's shared ground.
export function iconVoiceDebrief(size = 1024) {
  const b = [0.34, 0.62, 0.92, 0.66, 0.44];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${C.navy3}"/><stop offset="0.5" stop-color="${C.navy}"/><stop offset="1" stop-color="#06120D"/></linearGradient>
  <radialGradient id="h" cx="0.72" cy="0.78" r="0.7"><stop offset="0" stop-color="${C.green}" stop-opacity="0.95"/><stop offset="1" stop-color="${C.green}" stop-opacity="0"/></radialGradient>
</defs>
<rect width="1024" height="1024" fill="url(#g)"/>
<rect width="1024" height="1024" fill="url(#h)"/>
${b.map((h, i) => `<rect x="${206 + i * 72}" y="${512 - h * 220}" width="44" height="${h * 440}" rx="22" fill="#FFFFFF"/>`).join('')}
${[0, 1, 2].map(i => `<rect x="580" y="${408 + i * 92}" width="${[250, 250, 160][i]}" height="44" rx="22" fill="${i === 0 ? C.greenHi : '#FFFFFF'}"/>`).join('')}
</svg>`;
}

export function iconSGit(size = 1024) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${C.navy3}"/><stop offset="0.5" stop-color="${C.navy}"/><stop offset="1" stop-color="#0A0D24"/></linearGradient>
  <radialGradient id="h" cx="0.72" cy="0.78" r="0.7"><stop offset="0" stop-color="${C.indigo}" stop-opacity="0.95"/><stop offset="1" stop-color="${C.indigo}" stop-opacity="0"/></radialGradient>
</defs>
<rect width="1024" height="1024" fill="url(#g)"/>
<rect width="1024" height="1024" fill="url(#h)"/>
<rect x="212" y="212" width="600" height="600" rx="132" fill="none" stroke="#FFFFFF" stroke-width="44"/>
<line x1="430" y1="340" x2="430" y2="690" stroke="#FFFFFF" stroke-width="44" stroke-linecap="round"/>
<path d="M430 600 C430 520 600 540 600 440 V400" fill="none" stroke="${C.greenHi}" stroke-width="44" stroke-linecap="round"/>
<circle cx="430" cy="340" r="44" fill="#FFFFFF"/>
<circle cx="430" cy="690" r="44" fill="#FFFFFF"/>
<circle cx="600" cy="380" r="50" fill="${C.greenHi}"/>
</svg>`;
}
