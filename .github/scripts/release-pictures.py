#!/usr/bin/env python3
"""Pictures for a version's page: the screens that changed since the version before.

    release-pictures.py <new screens folder> <old screens folder> <out folder> [--most N] [--threshold F]

Both folders are unpacked `screens-<sha>` artifacts of screens.yml. For every screen id, the light
iPhone and light iPad pictures of the two sets are compared; a screen counts as changed when more
than the threshold (default 3 %) of the picture differs, which is above what the times printed on a
row change between two launches. A screen only the new set has is new.

Writes, for the N most changed screens (default 8), one JPEG each into the out folder: the iPhone
picture beside the iPad one, 560 px high. Prints a table of every screen with how much of it
differs, then the markdown to paste into versions/<version>/index.md, with CAPTION where the one
line saying what is new goes. A person or an agent looks at the pictures and writes the captions:
the script cannot know what is new, only that something is. Needs Pillow.
"""
import pathlib, sys
from PIL import Image, ImageChops

opts = sys.argv[1:]
args = [a for n, a in enumerate(opts) if not a.startswith("--") and not (n and opts[n - 1].startswith("--"))]
def opt(name, default):
    return type(default)(opts[opts.index(name) + 1]) if name in opts else default
if len(args) != 3:
    sys.exit(__doc__)
new, old, out = (pathlib.Path(a) for a in args)
MOST, THRESHOLD = opt("--most", 8), opt("--threshold", 0.03)
SETS = ["iphone-light", "ipad-light"]

def differs(a, b):
    """The share of the picture that differs, ignoring the status bar and small shifts of tone."""
    with Image.open(a) as x, Image.open(b) as y:
        size = (x.width // 4, x.height // 4)
        x, y = x.convert("L").resize(size), y.convert("L").resize(size)
    top = size[1] // 16
    diff = ImageChops.difference(x, y).crop((0, top, size[0], size[1]))
    changed = sum(diff.histogram()[25:])
    return changed / (diff.width * diff.height)

ids = sorted({f.name[len(s) + 1:-4] for s in SETS for f in new.glob(f"{s}-*.png")})
rows = []
for i in ids:
    # A set the old folder lacks altogether (a cancelled job) is not compared; a screen is new
    # only when the old folder has it in no set.
    pairs = [(new / f"{s}-{i}.png", old / f"{s}-{i}.png") for s in SETS]
    pairs = [(n, o) for n, o in pairs if n.exists() and o.exists()]
    if not pairs:
        share, state = 1.0, "new"
    else:
        share = max(differs(n, o) for n, o in pairs)
        state = "changed" if share >= THRESHOLD else "same"
    rows.append((share, i, state))
gone = sorted({f.name[len(s) + 1:-4] for s in SETS for f in old.glob(f"{s}-*.png")} - set(ids))

print("| Screen | Differs | |\n|---|---|---|")
for share, i, state in sorted(rows, reverse=True):
    print(f"| `{i}` | {share:.1%} | {state} |")
for i in gone:
    print(f"| `{i}` | | no longer pictured |")

picked = [r for r in sorted(rows, reverse=True) if r[2] != "same"][:MOST]
out.mkdir(parents=True, exist_ok=True)
HEIGHT = 560
print("\n## Pictures\n")
for share, i, state in picked:
    parts = []
    for s in SETS:
        f = new / f"{s}-{i}.png"
        if f.exists():
            im = Image.open(f).convert("RGB")
            parts.append(im.resize((round(im.width * HEIGHT / im.height), HEIGHT), Image.LANCZOS))
    gap = 16
    sheet = Image.new("RGB", (sum(p.width for p in parts) + gap * (len(parts) - 1), HEIGHT), "#7f7f7f")
    x = 0
    for p in parts:
        sheet.paste(p, (x, 0))
        x += p.width + gap
    name = f"{i}.jpg"
    sheet.save(out / name, quality=70, optimize=True)
    print(f"**CAPTION** (`{i}`, {'new' if state == 'new' else 'changed'})\n\n![The {i} screen on iPhone and iPad]({name})\n")
rest = [r[1] for r in sorted(rows, reverse=True) if r[2] != "same"][MOST:]
if rest:
    print("Also changed: " + ", ".join(f"`{i}`" for i in rest) + ".")
if not picked:
    print("No screen changed in this version.")
