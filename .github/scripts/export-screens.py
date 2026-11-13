#!/usr/bin/env python3
"""Export the screenshots in an .xcresult as <label>-<screen id>.png.

    export-screens.py <Tests.xcresult> <out dir> <label>      label: iphone-light, ipad-dark, ...
    export-screens.py --self-test

Uses `xcrun xcresulttool export attachments` (Xcode 16+), which writes the files plus a
manifest.json naming each one after its XCTAttachment. Carried over from PrompTugal__App__iOS.
"""
import json, pathlib, re, shutil, subprocess, sys, tempfile


def attachment_id(name: str) -> str:
    """The XCTAttachment name back from xcresulttool's suggested file name.

    xcresulttool puts "_<n>_<UUID>" before what it takes to be the extension, and a dotted id's
    last part looks like one:
        "record_0_<UUID>.png"             -> "record"
        "record-empty_0_<UUID>.png"       -> "record-empty"
        "note_0_<UUID>.finished"          -> "note.finished"
    """
    m = re.fullmatch(r"(.*?)_\d+_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}(\..*)?", name, re.I)
    if not m:
        return pathlib.Path(name).stem
    head, tail = m.group(1), m.group(2) or ""
    if tail.lower() == ".png":
        tail = ""
    return head + tail


if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
    u = "70EE4FB8-EA45-427B-A980-DF8C0874723C"
    cases = {f"record_0_{u}.png": "record", f"record-empty_0_{u}.png": "record-empty",
             f"note_0_{u}.finished": "note.finished", f"vault_1_{u}.detail": "vault.detail",
             f"record_0_{u}.recording": "record.recording", "plain.png": "plain",
             f"note_0_{u}.finished-end": "note.finished-end", f"lab_0_{u}.prompt": "lab.prompt", f"record_0_{u}.recording-discard": "record.recording-discard"}
    for given, want in cases.items():
        got = attachment_id(given)
        assert got == want, (given, got, want)
    print("ok")
    sys.exit(0)

result, out, label = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
out.mkdir(parents=True, exist_ok=True)
raw = pathlib.Path(tempfile.mkdtemp())
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", str(raw)],
               check=True)
manifest = json.loads((raw / "manifest.json").read_text())
count = 0
for test in manifest:
    for att in test.get("attachments", []):
        # Only our screenshots: skip failure debug descriptions (.txt) and screen recordings (.mp4).
        if not att["exportedFileName"].lower().endswith(".png"):
            continue
        name = att.get("suggestedHumanReadableName") or att["exportedFileName"]
        base = attachment_id(name)
        target = out / f"{label}-{base}.png"
        if target.exists():
            sys.exit(f"Two screenshots map to {target.name} (from {name!r})")
        shutil.copy(raw / att["exportedFileName"], target)
        count += 1
        print(target.name)
print(f"{count} screenshots", file=sys.stderr)
if count == 0:
    sys.exit("No screenshots found in the result bundle")
