# 051: An exploration: YouTube in the app, Spotify, and which other accounts to connect

**Status:** open, an exploration. No code. From the owner's note of 15 November 2026, 11:54, relayed by the
parent session. Written by the Lab session from what it knows of these platforms; **nothing here was checked
against the providers' current terms or documentation on the day**, and each point that a decision would
rest on is marked "to check".

The question behind it: a voice-first app that already hears "open the library" could as well hear "play
that talk about vaults" or "put some music on". What would that take, within the project's rules (Apple SDK
only; no backend of ours; nothing in the app may be a secret, since the build is public)?

## 1. Playing YouTube videos inside the app

**How it is done.** A `WKWebView` that loads YouTube's embedded player (the IFrame player, at
`youtube.com/embed/<video id>`), with inline playback allowed in the web view's configuration. `WebKit` is
Apple's; the app already uses a `WKWebView` in `WebVaultView`. No YouTube SDK and no key are needed to play
a video whose id is known.

**The rules, as understood (to check against the YouTube API Services terms and the developer policies):**

- The player must be YouTube's own, shown as it comes: its controls, branding and advertisements are not to
  be hidden, covered or altered.
- No playing in the background or with the screen off, and no separating the sound from the picture. For a
  voice-first app this is the one that matters: "play it while I drive with the phone locked" is not allowed
  through the embed. That is what YouTube Premium and YouTube Music sell.
- No downloading or keeping the video or its audio.
- A video's owner can switch embedding off, and some videos (much music) will not play embedded at all.
- The player must be at least a minimum size (remembered as 200 by 200 points; to check).

**Finding a video by voice is the harder half.** Playing needs an id. Getting from "that talk about vaults"
to an id means search, which is the YouTube Data API: an API key with a daily quota. A key in a public build
is not a secret, so it can be taken and its quota spent by anyone; restricting it to the app's bundle
identifier helps and is not proof. Three ways that need no key: play only links that are already in the
user's notes or pasted in; let the user paste or share a link to the app; or open YouTube's own search in
the web view and let the user choose.

**What Apple's review would look at (to check):** an app that is mainly a wrapper around someone else's
video service is refused; a player inside an app that does something else is common. Videos bring in content
the app does not control, which bears on the age rating.

**A first experiment that is clearly safe:** a Lab screen that takes a YouTube link, from a note or pasted,
and plays it in the embedded player, on screen, as YouTube provides it. Apple SDK only, no key, no account.
What it would teach: whether the embed behaves in a `WKWebView` on the three devices, and what happens to
the app's own listening while a video plays (the audio session again: see issue 047). **Not built**: the
parent session's brief was no code unless clearly safe, and the audio session question deserves the
microphone-turn work to land first.

## 2. Connecting Spotify

Four ways, from the least to the most:

| Way | What it gives | What it costs |
|---|---|---|
| Open the Spotify app by link | "Play X" becomes opening `https://open.spotify.com/...` (a universal link) or a `spotify:` address; Spotify takes over | Nothing: Apple SDK only (`UIApplication.open`), no account, no key. The user leaves the app. Needs an address for the thing to play, which is search again, unless the link is one the user already has |
| Apple Music through `MusicKit` or `MPMusicPlayerController` | Search of the Apple Music catalogue, playback in the app or through the system player, playback in the background, all with Apple's frameworks | The user needs an Apple Music subscription for catalogue playback; the app needs the MusicKit capability on its identifier and asks the user's permission. No third-party code |
| Spotify's Web API with OAuth | Search, the user's playlists, and control of playback on one of the user's devices | An app registered with Spotify and its client id in the build (public, which the PKCE flow is designed for: no client secret is needed). Sign-in through `ASWebAuthenticationSession`, which is Apple's. Controlling playback needs the user to have Spotify Premium, and a device where Spotify is already running. Tokens kept in the Keychain. Spotify's developer terms apply, and apps beyond a small number of test users need Spotify's approval (to check: the current quota rules) |
| Spotify's iOS SDK | Playback controlled from inside the app through the Spotify app on the same device | A third-party binary framework, which decision 4 in `CLAUDE.md` rules out without a written reason. It still needs the Spotify app installed and, for playback on demand, Premium |

**The comparison in one line each.** Opening by link is free and nearly useless without search. Apple Music
is the only one that is all Apple's and plays in the background, and it only helps a user who subscribes to
it. Spotify's Web API does the most for a Spotify user without any third-party code, at the price of an
account connection and Spotify's review. The Spotify SDK adds little over the Web API for a voice-first app
and breaks a standing rule.

**Is there a written reason for the Spotify SDK?** Not that this session can find. What it adds over the
Web API is waking the Spotify app and a steadier connection to it. That is a convenience, not a capability
the product needs.

**A suggestion, for the owner to decide:** if music is wanted at all, try Apple Music first (one capability,
no third party, and it is the same permission-and-capability shape the app already knows), and treat Spotify
as the second experiment through its Web API. Both would go behind a door, in the sense of issue 013: a
network door that names the one host each may talk to, and shows every request.

## 3. Which other accounts would be worth connecting, for a voice-first app

Judged by one test: does it turn something said into something done, or bring back something worth hearing,
without a backend of ours?

**Already on the device, with Apple's frameworks, no account of ours and no network:**

- **Reminders and Calendar** (`EventKit`). The Actions of a debrief are tasks with nowhere to go; "add that
  to my reminders" and "what is on tomorrow" are the most natural things to say to a voice note app. Full
  access is asked for and can be refused. This is the one this session would do first: it closes the loop
  that L06 opened, where tasks are found and then only read out.
- **Contacts** (`Contacts`). To recognise names in a note and in "send this to". The app has its own
  recipients; the address book would only add names, and it is a large permission for that.
- **Apple Music** (above).
- **Shortcuts and App Intents.** Not an account: the way Siri, the Action button and other apps reach into
  this one. Already listed as proposed in the reality file.
- **Files and iCloud Drive** (the document picker). To bring audio in and take notes out; no account work.
- **Mail and Messages** by their compose sheets (`MessageUI`). "Send this as an email": the user sees the
  draft and presses send, so nothing goes without a tap.

**Needing an account connection over the network (OAuth in `ASWebAuthenticationSession`, tokens in the
Keychain, the provider's review):**

- **A notes or tasks service the user already lives in** (Notion, Todoist, Things by its address scheme,
  Obsidian by files). Worth it only for the one the owner uses; each is its own integration.
- **GitHub.** For this project's own way of working: an issue from a voice note. Narrow, and useful to the
  owner today.
- **Slack or email by API.** Sending by voice into a channel. The compose sheets cover email without any
  account; Slack needs an app in the workspace.
- **Spotify** (above).

**Not worth connecting, in this session's view:** anything whose only purpose is to pull in more content to
summarise (feeds, social networks). It moves the app away from "my voice in, my notes out", and each one
brings a review and terms of its own.

## What every one of these has in common

- A token in the Keychain, on this device only, and a visible way to disconnect.
- A door: the code decides what is asked for, the model at most says what kind of thing was meant (as in
  L02 and L06), and every request is shown.
- Nothing sent anywhere without the person's own tap or their own standing switch, the rule L02 keeps.

## Decisions this needs from the owner

1. Is playing video on screen only (no background, no locked phone) worth having? If not, YouTube stops here.
2. Music: Apple Music first, Spotify by its Web API, or neither?
3. Reminders and Calendar through `EventKit`: build it as the next Lab experiment (L08)?
