import Foundation

/// How long one step took and how it ended.
struct StepRecord: Codable, Equatable, Sendable, Identifiable {
    enum Outcome: String, Codable, Sendable {
        case running, done, degraded, failed
    }

    let name: String
    var outcome: Outcome
    var seconds: Double
    var note: String

    var id: String { name }
}

/// One voice note taken through the pipeline. Kept in memory only in this build: nothing is saved.
struct DebriefRun: Codable, Equatable, Sendable {
    var source: String                 // "Recorded here" or the imported file's name
    var localeId: String
    var audioSeconds: Double?
    var transcript: Transcript?
    var debrief: String?
    /// Sections of a long note, when the note was read in parts.
    var sections: Int
    var debriefHasAllSections: Bool
    var steps: [StepRecord]
    var modelContextSize: Int?

    init(source: String, localeId: String) {
        self.source = source
        self.localeId = localeId
        self.sections = 0
        self.debriefHasAllSections = false
        self.steps = []
    }

    /// The debrief and the transcript as one markdown document, for sharing.
    var markdown: String {
        var out = "# Voice debrief\n\n"
        out += "Source: \(source). Language: \(localeId).\n\n"
        if let debrief { out += debrief.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" }
        if let transcript, !transcript.isEmpty {
            out += "## Transcript\n\n" + transcript.timedText + "\n\n"
        }
        out += "Transcribed and summarised on this device by Apple's models. Written by a model, not a stenographer: check anything that matters against the audio.\n"
        return out
    }
}
