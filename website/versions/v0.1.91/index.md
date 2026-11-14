# What changed in v0.1.91

Released 14 November 2026. Every push to the repository's `dev` branch is a release; this page was written by CI from the notes that came with it. [Every version](../index.md) · [What is built](../../built/index.md)

The voice game (Lab, L03: Play) lets go of the microphone as the control centre does: it stops listening when you leave the screen or the app goes to the background, never switches the audio off for the rest of the app, gives up if it was stopped while starting, and will not start while a voice note is being recorded. A results page on the site, [L03 results](../../lab/l03/index.md), is written from the logs the app shares: drop one in `website/lab/l03/runs/` and run the generator. No run yet.

Two ways to talk, at the owner's request: a lane (one way, sealed to their key, you cannot read it back) and a shared vault (both of you read and write the same encrypted files) each have an animated drawing, a small badge for any message or send, and a short explainer with both side by side. Ready to be placed on the send card, Messages and Agents.

Messages to Claude reads as a conversation: your notes on the right in the accent colour with their state beneath, Claude's replies on the left beside its conductor avatar. The picture sheet opens with who the picture goes to (you, an arrow, them), and its states take the house symbols and colours. A palette and a player sprite (your own avatar) are offered to the L03 game.

The vault list in the vault colour: each vault has an indigo badge (a shield for read and write, an eye for read only), and its status line carries a symbol and colour for where it is: in step with its server (green), not yet pushed or ahead (amber), push failed (red), on the server only (indigo). The words are unchanged.

Pictures of the screens are added to this page when the screens workflow has taken them for this version.
