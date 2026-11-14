#!/usr/bin/env python3
"""Draws the feature guides' pictures: numbered callouts with arrows on pictures of the screens.

    python3 website/admin/guides.py <VoiceDebrief screens> [<SGit Vaults screens>]

Each folder is an unzipped artifact: of screens.yml, and of sgit-app-screens.yml for the guides whose app
is SGit Vaults (files iphone-light-<screen>.png). Without the second folder those guides are left as they are.
A guide with a "set" draws from the folder given as <set>=<folder>, e.g. sgit-run-43592618173=/tmp/shots;
a guide whose folder is not given is left as it is. Reads
website/guides/guides.json and writes, for each step of each guide, one small JPEG at display size:
    website/guides/img/<guide>-<step>.jpg
    Apps/VoiceDebrief/Resources/vd-guide-<guide>-<step>.jpg   (the app's copy; resource names are unique)
    Apps/SGit/Resources/sg-guide-<guide>-<step>.jpg            (SGit Vaults' copy, for its own guides)
Run by hand when the pictures change, like release-pictures.py: the screens are not in the repository.
Needs Pillow. Content is in guides.json; this script is only the drawing.
"""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
WIDTH = 520                       # display size: a phone's column, twice a small thumbnail
INK = (230, 30, 80)               # one strong colour that reads on light and dark screens
HALO = (255, 255, 255)

def font(size):
    for name in ('/System/Library/Fonts/SFNSRounded.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                 '/Library/Fonts/Arial Bold.ttf'):
        try: return ImageFont.truetype(name, size)
        except OSError: pass
    return ImageFont.load_default()

def arrow(d, a, b, w):
    import math
    d.line([a, b], fill=HALO, width=w + 6)
    d.line([a, b], fill=INK, width=w)
    ang = math.atan2(b[1] - a[1], b[0] - a[0]); L = w * 4.5
    head = [b, (b[0] - L * math.cos(ang - 0.45), b[1] - L * math.sin(ang - 0.45)),
               (b[0] - L * math.cos(ang + 0.45), b[1] - L * math.sin(ang + 0.45))]
    d.polygon(head, fill=INK, outline=HALO)

def draw(src, callouts):
    im = Image.open(src).convert('RGB')
    W, H = im.size
    s = W / 736                    # sizes are for an iPhone picture 736 wide
    d = ImageDraw.Draw(im)
    r, w, f = int(26 * s), max(3, int(6 * s)), font(int(30 * s))
    for c in callouts:
        at = (c['at'][0] * W, c['at'][1] * H)
        lab = (c.get('label', c['at'])[0] * W, c.get('label', c['at'])[1] * H)
        if lab != at:
            import math
            dx, dy = at[0] - lab[0], at[1] - lab[1]; n = math.hypot(dx, dy) or 1
            start = (lab[0] + dx / n * r, lab[1] + dy / n * r)
            end = (at[0] - dx / n * r * 0.9, at[1] - dy / n * r * 0.9)
            arrow(d, start, end, w)
        d.ellipse([lab[0] - r - 3, lab[1] - r - 3, lab[0] + r + 3, lab[1] + r + 3], fill=HALO)
        d.ellipse([lab[0] - r, lab[1] - r, lab[0] + r, lab[1] + r], fill=INK)
        d.text(lab, str(c['n']), fill=HALO, font=f, anchor='mm')
    return im.resize((WIDTH, round(H * WIDTH / W)), Image.LANCZOS)

def main():
    plain = [a for a in sys.argv[1:] if '=' not in a]
    named = dict(a.split('=', 1) for a in sys.argv[1:] if '=' in a)
    if not plain and not named: sys.exit(__doc__)
    folders = {'VoiceDebrief': plain[0] if plain else None, 'SGit Vaults': plain[1] if len(plain) > 1 else None, **named}
    folders = {k: Path(v) for k, v in folders.items() if v}
    spec = json.loads((REPO / 'website/guides/guides.json').read_text())
    out_site, out_app = REPO / 'website/guides/img', REPO / 'Apps/VoiceDebrief/Resources'
    out_site.mkdir(parents=True, exist_ok=True)
    for g in spec['guides']:
        shots = folders.get(g.get('set', g['app']))
        if shots is None: continue
        for i, step in enumerate(g['steps'], 1):
            src = shots / f"iphone-light-{step['screen']}.png"
            if not src.exists(): sys.exit(f'missing {src}')
            im = draw(src, step['callouts'])
            outs = [out_site / f"{g['id']}-{i}.jpg", out_app / f"vd-guide-{g['id']}-{i}.jpg"]
            if g['app'] == 'SGit Vaults':
                outs.append(REPO / 'Apps/SGit/Resources' / f"sg-guide-{g['id']}-{i}.jpg")
            for p in outs:
                im.save(p, 'JPEG', quality=72, optimize=True, progressive=True)
            print(f"{g['id']}-{i}.jpg  {p.stat().st_size // 1024} KB")

if __name__ == '__main__':
    main()
