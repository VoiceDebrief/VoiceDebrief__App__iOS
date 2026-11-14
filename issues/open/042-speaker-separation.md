# 042: Telling speakers apart

**Status:** open, researched, needs the owner's decision. From the recordings made with a second person on
13 November 2026, which came out as one unbroken voice, and from the clinic article.

## What Apple's frameworks do (checked 14 November 2026)

- **iOS 26 has no speaker separation.** `SpeechAnalyzer` offers `SpeechTranscriber` (words, with times),
  `DictationTranscriber` and `SpeechDetector` (is anyone speaking). None says who is speaking. Third-party
  comparisons and developers building on it agree; no Apple statement says otherwise.
- **Nothing found for iOS 27 either.** A developer who searched the WWDC 2026 session catalogue reported no
  mention of diarization; the forum thread has no answer from Apple. This could still change in a later SDK.
- Apple's other frameworks (Sound Analysis, Vision, Natural Language) have no voice-identity feature either.

## The options

| Option | What it is | Cost |
|---|---|---|
| A. Wait for Apple | Nothing to build | Unknown wait; possibly never |
| B. A third-party model on the device | For example Hugging Face's `AnySpeechRecognizer` (`SpeakerDiarizer`, NVIDIA's Streaming Sortformer on Core ML, up to four speakers, built to sit inside `SpeechAnalyzer`), Argmax's SpeakerKit, or FluidAudio, which the open-source Swift Scribe app uses | Breaks decision 4 (Apple SDK only) and needs a written reason; a model download of about 250 MB; Sortformer is under NVIDIA's open model licence; untested on an iPhone by its authors |
| C. Ask the language model | Give Apple's model the transcript and ask it where the turns are | No new code or model; unreliable: it has no audio, only words. Useful for "two people were talking", not for who said what |
| D. Ask the people | A "conversation" mode in which the app records, and the person marks turns by tapping, or names the speakers afterwards on the transcript | Apple SDK only, reliable, and costs the person a little effort |

## Recommendation

D now, as the cheap and honest version: a conversation mode where the prompt stops saying "my own voice note",
and the person can name speakers on the transcript. Try B in the Lab only if the owner agrees to a written
exception to decision 4 for an on-device model, since everything stays on the device. Revisit A at each SDK.

Sources: Apple's WWDC25 session 277 on SpeechAnalyzer; developer forum thread 829621 ("Native diarization in
'27?"); Hugging Face, "Introducing AnySpeechRecognizer and AnyDecisionModel"; Argmax's SpeakerKit; the Swift
Scribe project.
