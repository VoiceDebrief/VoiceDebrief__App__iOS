# 117: sgit app: a record of every action, on every device

**Status:** open. **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

The owner, 14 November 2026: "add a full-blown observability here so you capture every single action that happens
on this app across my three devices" (a laptop, an iPad and an iPhone), reusing what VoiceDebrief has.

**Compiles and its tests pass (14 November 2026, `a4d6620`); done when a report from a device has been read:** VoiceDebrief's `UsageLog`, lane and lane encryption copied into
the app; every screen is timed and about thirty actions are recorded; Settings, Your activity shows them and
sends the report over the developer's lane as `sgit/usage/v1`, with the device model and a random install id so
that three devices can be told apart. The developer reads it with `tools/conductor/conductor.py drain`.

**Left:**

- Nobody has sent a report from a device, and the reader has not been run on one.
- Sending is by a button, on each device. To decide with the owner: a switch that sends on its own when the app
  opens (off by default), so that he does not have to remember on three devices.
- What an action carried (how many files, how large, how long an upload took, which error) is not recorded, only
  that it happened. The vault engine's own log (`VaultTrafficLog`, Settings, Every step) has the requests and
  timings and is not in the report.
- One copy of the lane code, in the shared package `SGitPeople`, when that lands; this app's copy then goes.
- A picture of the screen.
