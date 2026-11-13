# 019: Lanes are recipients, and the app has an inbox

**Status:** open. Asked for by the owner in a voice note, 13 November 2026 (6 min 44 s, recorded on an iPad).

Sending a note to somebody is a main activity, not a developer tool with caveats. A lane is a recipient: a
person, another device, a cloud session. Recipients have names, are easy to add (paste or scan a link), and a
finished note offers "send to <name>" as a first-class button. Per recipient, sending may be made automatic.

Two-way: each device has a vault, so each can have a lane of its own that others write to. The app gets an
inbox that looks and feels like one, where messages arriving and leaving can be seen.

## State, 13 November 2026 (v0.1.9, untried on a device)

Built: recipients with names; add by QR code (camera or a picture) or pasted link; one Send button per
recipient on a note; a recipient's QR code shown so it can be passed on; `tools/conductor/` for the receiving
side, so a new session or person can make an inbox and hand out its QR code.

The owner's two-step exchange, of which the first half is built:
1. The conductor gives its QR code (its lane: where to write, and its public key). The app scans it. Built.
2. The app gives its own QR code back (its public key, and a lane on its own vault), so the conductor can
   write to the app and, if wanted, be given a vault key encrypted to it. Not built: it needs the app's key
   pair (issue 018) and an inbox on the app's vault (011).

Also not built: remembering on a note who it was sent to; sending automatically per recipient; a link that
opens the app (a URL scheme or universal link), which would let "tap this link" replace "scan this code".

Extends 014 (names and a register). Replaces the design's position that a lane send is asked every time: the
owner now wants it encouraged, with automatic sending as an option per recipient.
