# What is in a file: an analysis layer for vaults

Proposed, 15 November 2026, at the owner's request. **None of this is built.** [What is built](../built/index.md) is the reality file. This page maps how the sgit app could add facts, transcripts and descriptions to each file in a vault, using Apple's models on the device only.

## The rule that makes it survive moves: everything hangs off the content hash

The app already keeps two things beside every photo and video it uploads, filed by the file's content hash, which depends only on its bytes:

- `.sgit/thumbs/<hash>.jpg`: a small picture, so a folder shows without fetching the file;
- `.sgit/meta/<hash>.json` (`sgit.ai/file-meta/v1`): size, dimensions, duration, codec, camera, the date taken.

Analysis follows the same rule, one file per analyser:

```
.sgit/analysis/<hash>/transcript.json     what is said, with times
.sgit/analysis/<hash>/transcript.vtt      the same as captions a player can show
.sgit/analysis/<hash>/vision.json         labels, text on screen, faces counted, codes read
.sgit/analysis/<hash>/summary.json        a title, a few sentences, tags
```

What follows from that:

- **A move or a rename changes nothing.** The bytes are the same, so the hash is the same, so the analysis is still found. The same is true of a copy: two copies share one analysis.
- **An edit is a new file.** Changed bytes have a new hash and get their own analysis; the old one stays with the old version in the history.
- **It is encrypted like everything else.** The server sees ciphertext. Whoever holds the vault key can read the analysis, and nobody else.
- **It is versioned and signed.** Adding an analysis is a commit, signed by the device that made it, so the history says what was analysed, when, and by which device.

Each record says what made it, so that a better model later can redo it without guessing:

```json
{
  "format": "sgit.ai/file-analysis/v1",
  "contentHash": "…",
  "analyser": "apple.speech.transcript",
  "analyserVersion": "iOS 26.1",
  "locale": "en-GB",
  "madeAt": "2026-11-15T20:00:00Z",
  "result": { … }
}
```

## What Apple's models can do with a video, on the device

| Question | Apple framework | What comes out | Notes |
|---|---|---|---|
| What is said? | Speech: `SpeechAnalyzer` with `SpeechTranscriber` (the VoiceDebrief app uses it today, in `SpeechFileTranscriber.swift`) | A transcript with a time for each phrase; captions | The video's sound is taken out first (`AVAssetExportSession` to `.m4a`) and handed to the same code as a voice note. Runs on the device, offline once the language model is downloaded |
| What is in it? | Vision: image classification, on a frame every few seconds and at each cut | Labels with confidence ("crowd", "stage", "car", "food") and when they appear | Cheap: frames are decoded at low resolution |
| What text is on screen? | Vision: text recognition | Slides, badges, signs ("KNOW THE REACH", "ATTENDEE Nikos") | Useful for search; the same works on photos |
| Who is in it? | Vision: face detection | How many faces, and when | **Counting only.** Recognising who a person is would be a separate, opt-in decision for the owner |
| Any codes? | Vision: barcode detection | QR codes and barcodes read in the frame | The attendee badge in the vault has one |
| Which frame is best? | Vision: aesthetics scores, saliency | A better thumbnail than the first frame | Also improves the gallery |
| What is it about? | Foundation Models (the on-device language model) | A short title, two or three sentences, tags | It takes text, not pictures, in the version the app builds against: it works from the transcript, labels and on-screen text above. One question at a time, through a function call, as the project's standing position asks |

**On the server side: no.** Apple's Private Cloud Compute is not something an app can call for its own work, and this project has no backend of its own by design. Everything above runs on the iPhone, iPad or Mac that has the file.

## Where and when it runs

1. **At upload, while the plain copy is still there.** This is how thumbnails are made today. It costs no download. Transcribing a long video takes minutes and battery, so it would be queued and run while the device is charging.
2. **Afterwards, on request, for files that came in another way** (the web Vault, the `sgit` command, an older build). "Analyse this folder" fetches each file once, analyses it, keeps the results and lets the copy go. The screen says how much it will fetch first ("5 videos, 2.1 GB").
3. **Never twice.** Before analysing, the app looks for `.sgit/analysis/<hash>/`. If another device or a teammate already did it, the work is done.

The same job fixes something visible today: **videos added without a stored thumbnail show a plain film icon**, because making one means fetching the whole file. A first version of "Analyse this folder" that only makes the missing thumbnails and facts would fix the owner's `movies` folder.

## What a person sees

- **In the viewer:** captions on a video from `transcript.vtt`, and the transcript under it, each line a jump to that moment.
- **In the (i) page:** the summary, the tags, the text found on screen, and which device made each and when.
- **In search** (not built yet either): find "KPMG" or "the talk about reach" across photos and videos, from an index built on the device from the analysis files.
- **In Ask this vault:** the model is handed the analysis, not the files.

## Build order (proposed)

1. **Missing thumbnails and facts**, made on request for files that have none. Small, and fixes the film icons.
2. **Transcripts of videos**, reusing the VoiceDebrief transcriber; captions in the viewer; the transcript in the (i) page.
3. **Vision labels and on-screen text** for photos and frames of videos.
4. **A summary and tags** from the on-device language model, working from 2 and 3.
5. **Search** across the vault, on the device.

## Questions for the owner

- Should analysis run at upload without asking, or only when asked? (Proposed: thumbnails and facts always; transcripts and labels when asked, per vault.)
- Is counting faces enough, or should recognising people be possible, opt-in, per vault?
- Which language should transcripts assume: the device's, or one set per vault?
