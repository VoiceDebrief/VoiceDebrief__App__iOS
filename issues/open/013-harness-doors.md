# 013: Doors: a harness inside the app

**Status:** open. See the article "A harness inside the app" and https://sharness.ai.

Network, file system, vault, keys, model, run: each a small component with a policy and a record. First the
model door (with issue 012), then the vault door (which has its log). A view that draws requests passing
through the doors, for iPad and Mac.

## Where it stands (13 November 2026)

The model door's first slice exists (`ModelDoor`, `Engine/LabModelDoor.swift`): a policy and a record, used by
the Lab only. Next: the debrief pipeline through the same door (the main session owns `DebriefSession`), the
vault door from its log, and the drawing.
