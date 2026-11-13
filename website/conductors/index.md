# Receiving notes: how to become a recipient

A person with VoiceDebrief on their phone can send a voice note, with its transcript and debrief, to anybody who has given them a **lane**. The receiver is called a conductor here: it may be a person at a computer or an agent session. This page is for the conductor.

> In test. The receiving script has been run against a live lane. Adding a recipient in the app by QR code is in build 0.1.9 and has not yet been tried on a device. [What is built](../built/index.md) is the record.

## What a lane is

An inbox that anybody holding its link can write to and only its owner can read. The link is one line of text, `sgi1.<vault>.<token>.<public key>`, optionally followed by `#` and a name:

- the **vault** says where the inbox is, on the vault server;
- the **token** allows writing to it and nothing else;
- the **public key** is the conductor's. Every note is encrypted to it on the sender's device.

The link is safe to hand out, show on a screen or put in a QR code. It cannot be used to list or read the inbox. The private key that opens the notes never leaves the conductor.

## Set up an inbox

The script is [`tools/conductor/conductor.py`](https://github.com/VoiceDebrief/VoiceDebrief__App__iOS/blob/dev/tools/conductor/conductor.py) in the repository. It needs Python and four packages.

```
pip install sgit-ai cryptography requests segno
python3 conductor.py --token <server access token> setup "Maria Silva"
python3 conductor.py qr maria.png
```

`setup` makes an RSA key pair, an sgit vault on the server and a lane on that vault. Creating a vault needs the server's access token; ask the owner of the project for it. Everything secret is written to `~/.voicedebrief-conductor` (change it with `--home`): **keep that folder out of any repository and never paste its contents anywhere.**

`qr` writes the link as a QR code. `link` prints it as text.

### For an agent session

Do not ask for the access token in chat. Ask for it as a credential for the server's host, to be sent in the header `x-sgraph-access-token`, and pass `--token proxy-injected`. Keep `--home` in the session's scratch space. Show the owner the QR code as an image.

## Give it to the sender

Any of these, whichever is to hand:

1. **Show the QR code** on a screen. In the app: Settings, Recipients, Scan their QR code.
2. **Send the picture** of the QR code. In the app: Choose a picture of their QR code.
3. **Send the link** as text. In the app: paste it.

The name in the code becomes the recipient's name in the app. From then on every note has a button, Send to Maria Silva.

A sender who already has a recipient can pass them on: the app shows each recipient's QR code.

## Read what arrives

```
python3 conductor.py drain notes/
```

Each note becomes a folder: the audio, `run.json` (the transcript, the debrief, how long each step took) and, if one was made, `clean.json`. The script checks each audio file against the hash sent with it, says if anything is incomplete, and marks what it fetched as processed.

`python3 conductor.py selftest` writes one message to the lane and reads it back, to check the inbox is alive.

## What is not here yet

- **The way back.** The app does not yet have a QR code of its own, so a conductor cannot write to the app or be given a vault. That needs the app's own key pair and an inbox on its vault, both in progress.
- **A link that opens the app.** Today the link is scanned or pasted. A link that adds the recipient when tapped is planned.
- **Checking who a key belongs to.** The app shows the key's fingerprint; compare it by eye if it matters. Tying a key to a person on the pki.sgit.ai register is planned.
