import Foundation

/// The words sent to the model. Derived from voicedebrief.ai's summary prompt
/// (VoiceDebrief__Website, website/app/prompts/summary-prompt.md, at 30ae8d9), shortened and made
/// more literal for a small on-device model.
enum DebriefPrompt {
    /// The language and tone the debrief is written in, by the locale that was transcribed.
    struct Voice: Equatable, Sendable {
        let language: String
        let tone: String
    }

    static func voice(forLocale id: String) -> Voice {
        let lower = id.lowercased().replacingOccurrences(of: "_", with: "-")
        if lower.hasPrefix("pt-br") {
            return Voice(language: "Brazilian Portuguese", tone: "Plain, direct Brazilian Portuguese. No marketing register.")
        }
        if lower.hasPrefix("pt") {
            return Voice(language: "European Portuguese", tone: "Plain, direct European Portuguese (Portugal, not Brazil). No marketing register.")
        }
        if lower.hasPrefix("en-us") {
            return Voice(language: "American English", tone: "Plain, direct American English. No marketing register, no exclamation marks.")
        }
        if lower.hasPrefix("en") {
            return Voice(language: "British English", tone: "Plain, direct British English. No marketing register, no exclamation marks.")
        }
        let name = Locale(identifier: "en_GB").localizedString(forIdentifier: id) ?? id
        return Voice(language: name, tone: "Plain and direct. No marketing register.")
    }

    static let sections = ["## Key points", "## Actions", "## In one sentence"]

    /// The whole debrief from a transcript that fits in one request.
    static func debrief(transcript: String, voice: Voice) -> String {
        """
        Write a summary of the voice note transcript below, in markdown.

        Structure it exactly as:

        ## Key points
        3 to 6 bullet points with what the speaker actually said: concrete facts, decisions, numbers and names.

        ## Actions
        Any tasks, follow-ups or requests mentioned, each as "- [who] what". If there are none, write "- none mentioned".

        ## In one sentence
        One plain sentence a busy person could read instead of listening to the note.

        Rules: use only what is in the transcript. Do not invent or embellish. Keep names, numbers and technical terms exactly as spoken.
        Write the whole summary in \(voice.language), including what follows each heading. Keep the three headings exactly as written above.
        Tone: \(voice.tone)

        Transcript (each line starts with its time):
        \(transcript)
        """
    }

    /// Notes on one section of a long transcript, to be merged later.
    static func notes(section: Int, of total: Int, transcript: String, voice: Voice) -> String {
        """
        This is part \(section) of \(total) of a voice note transcript. List what the speaker said in this part.

        Write up to 6 bullet points, each starting with "- ": concrete facts, decisions, numbers and names.
        Then list any tasks, follow-ups or requests, each as "- ACTION [who] what". If there are none, list none.

        Rules: use only what is in this part. Do not invent or embellish. Write in \(voice.language).

        Transcript part \(section) (each line starts with its time):
        \(transcript)
        """
    }

    /// The debrief from the notes on every section.
    static func merge(notes: String, voice: Voice) -> String {
        """
        Below are notes on each part of one voice note, in order. Write one summary of the whole note, in markdown.

        Structure it exactly as:

        ## Key points
        3 to 6 bullet points with the most important things the speaker said: concrete facts, decisions, numbers and names.

        ## Actions
        Every line marked ACTION in the notes, each as "- [who] what". If there are none, write "- none mentioned".

        ## In one sentence
        One plain sentence a busy person could read instead of listening to the note.

        Rules: use only what is in the notes. Do not invent or embellish. Keep names and numbers exactly as written.
        Write the whole summary in \(voice.language). Keep the three headings exactly as written above.
        Tone: \(voice.tone)

        Notes:
        \(notes)
        """
    }

    /// Whether a debrief has the three headings, in order. A model that drifts is reported, not hidden.
    static func hasAllSections(_ markdown: String) -> Bool {
        var from = markdown.startIndex
        for heading in sections {
            guard let found = markdown.range(of: heading, range: from..<markdown.endIndex) else { return false }
            from = found.upperBound
        }
        return true
    }
}
