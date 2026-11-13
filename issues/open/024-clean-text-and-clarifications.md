# 024: A clean text instead of a summary, with questions where the note is unclear

**Status:** open. The owner's idea, 13 November 2026. A first version is in v0.1.8, untried on a device.

Checked against Apple's documentation and developer forum, 13 November 2026: item 1 below is not possible
today. `AnalysisContext.contextualStrings` exists, but only `DictationTranscriber` uses it; `SpeechTranscriber`,
which the app uses, ignores it. So the words go to the language model instead (items 2 and 3, built). Not built:
playing a question's audio, the glossary in a vault, doing this while recording.

The transcript hears "vault" as "vote" and "volt"; the summary then repeats the mistake and loses detail.
Proposed instead of, or beside, the debrief:

1. **Fix it at the source.** Give the speech model the user's own words (vault, lane, sgit, names) if
   `SpeechAnalyzer` accepts contextual strings. To be verified against Apple's documentation.
2. **A clean text.** The note rewritten in full sentences, a passage at a time, nothing left out: false starts
   and repetitions removed, known terms corrected from a glossary. The glossary is the start of the semantic
   graph (021) and lives in the vault, so it follows the user between devices.
3. **Questions.** The model marks the passages it could not make sense of, as structured output, and the app
   asks the speaker about those: by showing the passage and playing its audio. The answers go into the glossary.
4. **Nothing is replaced.** The transcript as heard is always kept; the clean text shows what it changed.

To find out: how often the on-device model "corrects" something that was right; whether it can mark its own
doubt usefully; whether a passage at a time is fast enough to do while recording.
