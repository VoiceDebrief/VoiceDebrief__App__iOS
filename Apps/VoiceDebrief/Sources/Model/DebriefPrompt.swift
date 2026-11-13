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

    /// A note with fewer words than this is not sent to the model: there is nothing to summarise, and
    /// a small model asked anyway repeats the note back or invents something (first runs, 13 Nov 2026).
    static let minimumWords = 25

    static func wordCount(_ lines: [TranscriptLine]) -> Int {
        lines.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
    }

    /// The shape the model fills in. No quotation marks anywhere: a small model copies them into its answer.
    private static let shape = """
        ## Key points
        - one bullet for each thing said that matters: facts, decisions, numbers, names

        ## Actions
        - one bullet for each task or follow-up, starting with who does it in square brackets

        ## In one sentence
        One plain sentence a busy person could read instead of listening to the note.
        """

    private static func rules(_ voice: Voice, source: String) -> String {
        """
        Rules:
        - Keep the three heading lines exactly as they are above, in that order: ## Key points, ## Actions, ## In one sentence.
        - Use only what is in the \(source). Do not invent or embellish. Do not copy a whole line as a bullet: say what it means.
        - Write between 1 and 6 key points. A short note has few.
        - This is my own voice note: I recorded it and I am the one reading the summary. Write the points as plain statements with no subject, for example: Testing the new workflow. Never write the word Speaker.
        - Under Actions, my own tasks start with [me]. Use a name in the brackets only when I name someone else.
        - An action is something somebody has to do later. A passing remark or a hope is not an action. If there are no actions, the only bullet under Actions is: - none mentioned
        - Do not put quotation marks around bullets. Ignore filler words such as um and uh.
        - Keep names, numbers and technical terms exactly as spoken.
        - Write everything under the headings in \(voice.language). Tone: \(voice.tone)
        """
    }

    /// The whole debrief from a transcript that fits in one request.
    static func debrief(transcript: String, voice: Voice) -> String {
        """
        Summarise my voice note, whose transcript is at the end, in markdown, in exactly this shape:

        \(shape)

        \(rules(voice, source: "transcript"))

        Transcript (each line starts with its time):
        \(transcript)
        """
    }

    /// Notes on one section of a long transcript, to be merged later.
    static func notes(section: Int, of total: Int, transcript: String, voice: Voice) -> String {
        """
        This is part \(section) of \(total) of the transcript of my own voice note. List what is said in this part, as plain statements with no subject. Never write the word Speaker.

        Write up to 6 bullets, each starting with a hyphen: facts, decisions, numbers and names.
        Then one bullet for each task or follow-up, each starting with a hyphen and the word ACTION, then who does it in square brackets. My own tasks are [me].

        Rules: use only what is in this part. Do not invent or embellish. A passing remark is not an action. No quotation marks. Write in \(voice.language).

        Transcript part \(section) (each line starts with its time):
        \(transcript)
        """
    }

    /// The debrief from the notes on every section.
    static func merge(notes: String, voice: Voice) -> String {
        """
        Below are notes on each part of my own voice note, in order. Write one summary of the whole note, in markdown, in exactly this shape:

        \(shape)

        \(rules(voice, source: "notes"))
        - Every line marked ACTION in the notes is an action.

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
