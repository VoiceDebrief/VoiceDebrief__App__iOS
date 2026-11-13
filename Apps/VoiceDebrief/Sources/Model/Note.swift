import Foundation

/// One recording and what was made from it, as the library keeps it. A note exists from the moment
/// the recording stops: before there is a transcript, and whether or not there is ever a debrief.
struct Note: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    var run: DebriefRun
    /// The audio file's name inside the note's folder, if the audio is kept.
    var audioName: String?
    /// True from Stop until the pipeline finishes. A note still marked so after a relaunch was interrupted.
    var processing: Bool
    /// The note rewritten as clear sentences, if that has been asked for (an experiment, issue 024).
    var clean: CleanText? = nil
    /// Each time this note was saved into a vault, newest last.
    var saves: [NoteSave]? = nil
    /// Why the last automatic save did not happen, in plain words.
    var saveProblem: String? = nil

    /// What a list shows: the debrief's one sentence, else the first words spoken, else when it was made.
    var title: String {
        if let debrief = run.debrief, let sentence = Note.oneSentence(in: debrief) { return sentence }
        if let first = run.transcript?.lines.first?.text {
            let all = first.split(separator: " ")
            let words = all.prefix(12).joined(separator: " ")
            if !words.isEmpty { return all.count > 12 ? words + "…" : words }
        }
        return processing ? "Voice note, not yet transcribed" : "Voice note with no words found"
    }

    /// The line under "In one sentence", if the debrief has one.
    static func oneSentence(in debrief: String) -> String? {
        let lines = debrief.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let heading = lines.firstIndex(where: { $0.lowercased().hasSuffix("in one sentence") && $0.hasPrefix("#") }) else { return nil }
        for line in lines[(heading + 1)...] where !line.isEmpty {
            if line.hasPrefix("#") { return nil }
            let cleaned = DebriefMarkdown.clean(line.hasPrefix("- ") ? String(line.dropFirst(2)) : line)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    /// "On this device", or the plain reason the note is not finished.
    var stateLine: String {
        if processing { return "Interrupted: open it to run it again" }
        if run.transcript == nil || run.transcript?.isEmpty == true { return "No words found" }
        if run.debrief == nil {
            let why = run.steps.last(where: { $0.name == "Debrief" })?.note ?? ""
            if why.hasPrefix("Too short") { return "Too short to summarise" }
            if !why.isEmpty { return "Transcript only: no debrief" }
            return "Transcript only"
        }
        return "On this device"
    }
}

/// One save of a note into a vault.
struct NoteSave: Codable, Equatable, Sendable {
    let vaultId: String
    let vaultName: String
    let at: Date
}

enum NoteGrouping {
    /// Notes newest first, grouped by calendar day, each group labelled "Today", "Yesterday" or the date.
    static func byDay(_ notes: [Note], now: Date = Date(), calendar: Calendar = .current) -> [(label: String, notes: [Note])] {
        var groups: [(day: Date, notes: [Note])] = []
        for note in notes.sorted(by: { $0.createdAt > $1.createdAt }) {
            let day = calendar.startOfDay(for: note.createdAt)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].notes.append(note)
            } else {
                groups.append((day, [note]))
            }
        }
        let today = calendar.startOfDay(for: now)
        return groups.map { group in
            let days = calendar.dateComponents([.day], from: group.day, to: today).day ?? 0
            let label: String
            if days == 0 {
                label = "Today"
            } else if days == 1 {
                label = "Yesterday"
            } else {
                label = group.day.formatted(date: .complete, time: .omitted)
            }
            return (label, group.notes)
        }
    }
}
