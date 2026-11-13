#!/usr/bin/env python3
"""Contact sheets and an index for a folder of screenshots named <device>-<appearance>-<id>.png.

    contact-sheet.py <folder> [<expected ids, comma-separated>]

Writes into the folder:
    contact-<device>-<appearance>.png   every screen of that set as labelled thumbnails, one picture
    index.md                            a table: one row per screen id, one column per set

and prints index.md, which screens.yml appends to the job summary. A summary cannot show a
picture that lives inside an artifact, so there the contact sheet is the table; the pictures
are the contact-*.png files. Exit 1 if a set lacks an expected id. Needs Pillow.
"""
import pathlib, re, sys
from PIL import Image, ImageDraw, ImageFont

folder = pathlib.Path(sys.argv[1])
expected = [i for i in (sys.argv[2].split(",") if len(sys.argv) > 2 else []) if i]
NAME = re.compile(r"(iphone|ipad)-(light|dark)-(.+)\.png")

sets = {}
for f in sorted(folder.glob("*.png")):
    m = NAME.fullmatch(f.name)
    if m:
        sets.setdefault((m.group(1), m.group(2)), {})[m.group(3)] = f

def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()

def sheet(device, appearance, shots):
    ids = [i for i in expected if i in shots] + sorted(i for i in shots if i not in expected)
    thumb_h = 520 if device == "iphone" else 360
    columns = 6 if device == "iphone" else 4
    pad, label_h = 16, 26
    thumbs = []
    for i in ids:
        im = Image.open(shots[i]).convert("RGB")
        w = max(1, round(im.width * thumb_h / im.height))
        thumbs.append((i, im.resize((w, thumb_h), Image.LANCZOS)))
    cell_w = max(t.width for _, t in thumbs)
    rows = -(-len(thumbs) // columns)
    title_h = 40
    canvas = Image.new("RGB", (pad + columns * (cell_w + pad), title_h + pad + rows * (thumb_h + label_h + pad)), "#7f7f7f")
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 10), f"{device}, {appearance}: {len(thumbs)} screens", fill="white", font=font(22))
    for n, (i, t) in enumerate(thumbs):
        x = pad + (n % columns) * (cell_w + pad)
        y = title_h + pad + (n // columns) * (thumb_h + label_h + pad)
        draw.text((x, y), i, fill="white", font=font(16))
        canvas.paste(t, (x, y + label_h))
    out = folder / f"contact-{device}-{appearance}.png"
    canvas.save(out, optimize=True)
    return out

order = [k for k in [("iphone", "light"), ("iphone", "dark"), ("ipad", "light"), ("ipad", "dark")] if k in sets]
missing = []
lines = []
if not order:
    lines.append("No screenshots were produced.")
else:
    for key in order:
        sheet(*key, sets[key])
    all_ids = expected + sorted({i for s in sets.values() for i in s} - set(expected))
    lines.append("| Screen | " + " | ".join(f"{d}, {a}" for d, a in order) + " |")
    lines.append("|---|" + "---|" * len(order))
    for i in all_ids:
        cells = []
        for key in order:
            f = sets[key].get(i)
            if f:
                with Image.open(f) as im:
                    cells.append(f"{im.width}x{im.height}")
            else:
                cells.append("**missing**")
                missing.append(f"{key[0]}-{key[1]}-{i}")
        lines.append(f"| `{i}` | " + " | ".join(cells) + " |")
    lines.append("")
    lines.append("Files: `<device>-<appearance>-<screen>.png`, and one `contact-<device>-<appearance>.png` per set.")
for key in [("iphone", "light"), ("iphone", "dark"), ("ipad", "light"), ("ipad", "dark")]:
    if key not in sets:
        missing.append(f"{key[0]}-{key[1]} (the whole set)")
if missing:
    lines.append("")
    lines.append("Missing: " + ", ".join(missing))
text = "\n".join(lines) + "\n"
(folder / "index.md").write_text(text)
print(text)
sys.exit(1 if missing else 0)
