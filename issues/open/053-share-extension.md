# 053: Receive a voice note from the share sheet (WhatsApp)

**Status:** open: built on `work/share`, waiting for the owner's identifiers and a device. Asked for by the owner on
17 November 2026: forward a voice note from WhatsApp into VoiceDebrief through the iOS share sheet. The relaunch
article promises it ("notes received from the share sheet, WhatsApp voice notes too").

## How it works

1. **The extension only takes the file in.** `ShareExtension` (bundle `ai.voicedebrief.app.share`) appears in the
   share sheet for audio and films (`public.audio`, `public.movie`, `public.audiovisual-content`, and
   `org.xiph.opus` and `org.xiph.ogg-audio`, which the app and the extension declare as imported types for `.opus`,
   `.ogg` and `.oga`). It reads the file's first bytes and says at once if it is a format that cannot be read yet
   (Ogg Vorbis, WebM); WebM is not offered as a type, since it would only be refused. It shows the file's name, length and size,
   "Debrief in VoiceDebrief" and Cancel. On "Debrief" it copies the file, file to file, into the App Group container
   (`group.ai.voicedebrief`) with a small JSON record beside it (`Shared/ShareInbox.swift`), posts a Darwin
   notification, and says "Kept. Open VoiceDebrief".
2. **The app does the rest.** On opening, on becoming active, and on that notification while it runs, the app takes
   each waiting file into the library as a note (`DebriefSession.takeShared`), and the normal pipeline runs: the Ogg
   Opus decode (issue 009), transcript, debrief, and saving to a vault as the settings say (`AutoSave`).
3. **Never lose a file.** A parcel is written into `<id>.partial/` and renamed when complete; it leaves the
   container only after its note's `note.json` is written. If the app stops in between, the next opening can make the
   note twice, never zero times. A folder whose record cannot be read is left alone, never deleted.

What it does not do: open the app by itself. Apple gives a share extension no supported way to open its app, so the
sheet says to open VoiceDebrief. A notification ("tap to debrief") would need the app to ask for permission first;
not done.

## Signing, and what the owner must do

**17 November: the owner has registered all three below, and it works.** The signing dry run in ios run 427 on
`work/share` archived the app with `ai.voicedebrief.app.share` inside and exported it for App Store Connect, both
signed with the App Group, by cloud-managed signing and the existing API key: `EXPORT SUCCEEDED`, "Signed for App
Store Connect with every extension and entitlement". No second profile to make by hand and no other step needed. The extension and the App Group are in both targets' entitlements. Until they are registered in the developer
portal, Apple will not sign them, so `scripts/release/testflight.sh` now tries with them and, if signing fails,
uploads the same build **without the extension and without the App Group** (the app as it was before), saying so in
the job summary under "TestFlight: signed WITHOUT the share extension". TestFlight keeps working either way. A push
to `work/share` also runs a signing dry run (nothing uploaded) to show whether the portal is ready.

In the Apple Developer account (developer.apple.com, Certificates, Identifiers & Profiles, Identifiers):

1. The plus, **App Groups**, Continue: description `VoiceDebrief`, identifier `group.ai.voicedebrief`. Register.
2. **`ai.voicedebrief.app`** (VoiceDebrief): tick **App Groups**, Configure, choose `group.ai.voicedebrief`,
   Continue, Save (confirm the change to the profiles).
3. The plus, **App IDs**, App: description `VoiceDebrief Share`, Bundle ID explicit `ai.voicedebrief.app.share`,
   tick **App Groups**, Configure, choose `group.ai.voicedebrief`, Continue, Register.

Nothing in App Store Connect and no new secret: the extension ships inside the app, and cloud-managed signing makes
the profiles with the API key CI already has. The next build after that carries the extension; the summary then
says "Signed for App Store Connect with every extension and entitlement" (dry run) or "Uploaded" without the
WITHOUT line.

## Left

- The first device test: share a WhatsApp voice note, see the sheet, open the app, get the note.
- If VoiceDebrief does not appear in WhatsApp's share sheet, the types WhatsApp registers are not the ones above;
  the parcel's `typeIdentifier` records what was offered when it does appear.
- Pictures of the sheet: a UI test cannot launch an extension alone; a device is the test.
