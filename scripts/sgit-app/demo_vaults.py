#!/usr/bin/env python3
"""Writes Apps/SGit/Resources/sg-demo-vaults.json: the published vaults listed at
https://sgit.ai/demos/vaults/, each with its public read key, for the sgit app's gallery.

Reads the page's Markdown twin (index.md) and each vault's own page (<slug>/index.md), where the
read key is published on purpose under the sgit_public_read_ prefix. Run by hand; the app also
fetches the list live and uses this file when it cannot.

    python3 scripts/sgit-app/demo_vaults.py
"""
import json, re, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = "https://sgit.ai/demos/vaults/"
OUT = Path(__file__).resolve().parents[2] / "Apps/SGit/Resources/sg-demo-vaults.json"
HEAD = re.compile(r"^\[(.+?)\]\(([^)]+?)/index\.md\)`([a-z0-9]+)`$")


def row(line):
    """A table row: number, link with the vault id, what it is (which may hold a |), category, files, size, date."""
    if not re.match(r"^\| \d+ \| ", line):
        return None
    cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
    if len(cells) < 7:
        return None
    head = HEAD.match(cells[1])
    if not head or not re.match(r"\d{4}-\d{2}-\d{2}$", cells[-1]):
        return None
    name, slug, vault = head.groups()
    return (cells[0], name, slug, vault, " | ".join(cells[2:-4]), cells[-4], cells[-3], cells[-2], cells[-1])
KEY = re.compile(r"sgit_public_read_[0-9a-f]{64}:[a-z0-9]{4,24}")


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "sgit-app-catalogue"}), timeout=30) as r:
        return r.read().decode("utf-8")


def main():
    rows = []
    for line in get(BASE + "index.md").splitlines():
        found = row(line)
        if not found:
            continue
        number, name, slug, vault, summary, category, files, size, published = found
        page = get(f"{BASE}{slug}/index.md")
        keys = [k for k in KEY.findall(page) if k.endswith(":" + vault)]
        if not keys:
            print(f"no read key on {slug}; left out", file=sys.stderr)
            continue
        rows.append({"number": int(number), "name": name, "slug": slug, "vault": vault, "summary": summary,
                     "category": category, "files": int(files), "size": size, "published": published,
                     "page": f"{BASE}{slug}/index.html", "readKey": keys[0]})
    data = {"format": "sgit.ai/demo-vaults/v1", "source": BASE + "index.html",
            "fetched": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "vaults": rows}
    OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(rows)} vaults written to {OUT}")


if __name__ == "__main__":
    main()
