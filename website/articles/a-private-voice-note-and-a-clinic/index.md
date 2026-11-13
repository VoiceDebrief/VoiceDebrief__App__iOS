# A private voice note, and what it would take to use it in a clinic

**Kind:** an idea, with corrections. **From:** a conversation recorded in the app on 13 November 2026 between the owner and a clinician, who asked for it to be written down and drawn. Written up by the agent working on the repository, which has also corrected the places where the conversation described the plan as if it were built, or said more than is true.

> This is not legal, regulatory or clinical advice. It says what the software does and does not do, so that the people who are qualified to decide can decide.

[![A patient's device records, transcribes and summarises a voice note without the internet and encrypts it into a vault. A clinician's QR code gives the patient the clinician's public key; a note sealed to that key crosses a server that cannot read it and is opened on the clinician's device.](../../assets/diagrams/a-private-voice-note.svg)](../../assets/diagrams/a-private-voice-note.svg)

## The idea in one paragraph

VoiceDebrief is one example of a pattern that could carry other things than voice notes. A person's own device does the work: it records, a model **on the device** turns speech into text, and a second model on the device summarises it. Nothing has to leave the device for any of that, so it works offline. What the person chooses to keep is encrypted on the device into a vault that only their key opens. What they choose to send goes to one other person, encrypted to that person's public key, so that the server carrying it holds bytes it cannot read. There is no account with the company that made the app. The proposal is to try this between a patient and a clinician.

## The workflow, step by step

| Step | What happens | Today |
|---|---|---|
| 1. Speak | The recording is written into the app's own storage as it is spoken | Works |
| 2. Words | Apple's speech model, on the device, produces a transcript with times | Works. English tried; other languages untried |
| 3. Summary | Apple's language model, on the device, writes key points, actions and one sentence | Works, with faults: see below |
| 4. Keep | The note is encrypted on the device into a vault as one signed commit | Works by hand; automatic saving is written, untried |
| 5. Exchange keys | The clinician shows a QR code: their public key and the address of their inbox. The patient scans it once | In build 0.1.9, untried on a device. The receiving side exists as a script, not an app |
| 6. Send | The note is encrypted on the patient's device to the clinician's key and left in their inbox | Works: every note in this project's testing has travelled this way |
| 7. Open | The clinician's device fetches it and opens it with a private key that never left that device | Works, in the script |
| 8. The way back | The clinician writes to the patient, or is given access to part of the patient's vault | Designed, not built |

## What the conversation got right

- **The models run on the device, so it works offline and the audio need not go anywhere.** True of both Apple's speech model and its language model as the app uses them.
- **No login with us.** The app is installed with an Apple ID, which the developer does not see. The developer cannot tell one user from another, and is not meant to.
- **A passkey is unlocked by a face or a finger and kept by Apple so that only your own devices can use it.** True: passkeys live in iCloud Keychain, which is end-to-end encrypted.
- **A vault's key can be taken out and the vault opened in a browser.** True: the vault format is sgit's, and a vault made by the app has been read back that way.
- **The clinician's side is the same design in a different app.** That is the intention: the keys, vaults and inboxes do not change; the screens do.

## What needs correcting

1. **"The model transcribes and separates the speakers."** It transcribes. It does not tell speakers apart: the recording this article came from, with two people talking, came out as one unbroken voice. The app treats every note as one person's memo.
2. **"The passkey is the same one I use for iCloud."** No. A passkey belongs to one site or app. The one used here would be made for this purpose and is separate from the Apple ID. What is shared is where it is kept (iCloud Keychain) and how it is unlocked (Face ID or Touch ID).
3. **"The vault key is made from the passkey."** That is the design, and it already works on the web at pki.sgit.ai. In the app, the arithmetic exists and is tested against published examples, but the sign-in itself is not built. Today the app keeps vault keys in the device's Keychain.
4. **"Because it is on the device and encrypted, it is GDPR compliant."** This is the one to be careful with, and the next section is about it.
5. **"You take a photo of the doctor's QR code and now you have authorised the doctor."** Scanning a code tells the app which key to encrypt to. It does not prove whose key it is. If somebody else's code were shown, the note would go to them, perfectly encrypted.

## On data protection

Doing the work on the device and encrypting before anything leaves it removes a large part of the usual risk: there is no company server holding recordings, no third-party model receiving them, and a breach of the storage server yields ciphertext. Those are real advantages and they are the reason for the design.

They do not make a service "compliant" by themselves. If a clinic used this with patients:

- **Health data is a special category** under the GDPR. Processing it needs a lawful basis and one of the specific conditions for special-category data, whatever the technology.
- **The clinic would be a controller** for what it receives and keeps, with the duties that follow: telling patients what happens to their data, keeping it only as long as needed, answering requests for access and erasure, recording what it does.
- **Encrypted data on a server is still personal data being processed**, and whoever runs that server is acting for somebody. Where it is, and under what contract, still has to be answered. The server not being able to read it is a strong safeguard, not an exemption.
- **A data protection impact assessment** would very probably be expected before use with patients.
- **Losing the key is losing the data.** That is a property of the design. For a clinical record it is also an availability risk that has to be planned for: recovery, and what happens when a patient loses a phone.

The honest summary: this design makes many of the hard questions easier to answer well. It does not answer them for you.

## What a clinic would need that does not exist yet

- **Knowing who a key belongs to.** A register of people and their public keys, where a clinician is verified once by an accountable body and patients' apps check that. The project has this in design (pki.sgit.ai, with delegations that expire), not in the app.
- **The way back.** The patient's own code, so that a clinician can write to a patient, and so that a patient can give a clinician access to one vault and take it away again.
- **Taking access away.** Sending to a key cannot be undone. Shared vaults need keys that can be changed when somebody leaves.
- **A record of who did what.** Every change to a vault is a signed commit, which is a good foundation for an audit trail. Reading is not recorded.
- **Treating the summary as what it is.** In testing, the on-device model has turned a passing remark into a task, mixed up who said what, and misheard names. The audio and the transcript are the record; a summary would need a person to check it before it went anywhere near a clinical note. Whether software that summarises a consultation is regulated as a medical device depends on what it is claimed to do, and is a question for a regulatory specialist.
- **More than one speaker.** A consultation is a conversation.
- **Large files.** A scan is not a voice note. Support for files over 4 MB now exists in the vault engine and is being built into a second app for sharing files.

## A first experiment that would be worth doing

Small, with no real patient data:

1. A clinician and a colleague acting as a patient, each with the app (or the clinician with the receiving script).
2. Exchange codes. The "patient" records three notes of the kind a real one might: a symptom diary entry, a question before an appointment, an account of a week on a new medicine.
3. Look at what arrives, and judge three things: is the transcript good enough to rely on; is the summary safe to show a clinician; how long did the whole thing take, in presses and in seconds.

That would say whether the pattern is worth taking to the people who would have to approve it.
