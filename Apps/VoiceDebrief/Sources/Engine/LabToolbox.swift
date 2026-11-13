import Foundation

/// What a tool hands back to the model, and whether it could do what was asked.
struct LabToolResult: Equatable, Sendable {
    let text: String
    let ok: Bool
}

/// A note as the Lab's tools see it: copied out of the library before a run, so a tool never
/// touches the library itself and nothing a tool does can change a note.
struct LabNote: Equatable, Sendable {
    let id: String
    let createdAt: Date
    let title: String
    let transcript: String?
}

/// The logic of the Lab's tools, with no model in sight. Each tool reads; none writes.
struct LabToolbox: Sendable {
    /// Newest first.
    let notes: [LabNote]
    /// A fixed time for tests; nil reads the clock.
    var fixedNow: Date?
    var timeZone: TimeZone = .current

    /// The most notes one listing returns, and the most characters of one transcript: a tool's
    /// result is counted against the model's small context.
    static let listLimit = 20
    static let transcriptLimit = 1500

    init(notes: [LabNote], fixedNow: Date? = nil, timeZone: TimeZone = .current) {
        self.notes = notes.sorted { $0.createdAt > $1.createdAt }
        self.fixedNow = fixedNow
        self.timeZone = timeZone
    }

    /// A copy of the library as it is now.
    @MainActor
    init(store: NoteStore) {
        self.init(notes: store.notes.map {
            LabNote(id: $0.id, createdAt: $0.createdAt, title: $0.title, transcript: $0.run.transcript?.timedText)
        })
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    func currentDateTime() -> LabToolResult {
        let now = fixedNow ?? Date()
        let text = formatter("EEEE d MMMM yyyy, HH:mm").string(from: now) + ", time zone " + timeZone.identifier
        return LabToolResult(text: text, ok: true)
    }

    func listNotes(limit: Int) -> LabToolResult {
        guard !notes.isEmpty else { return LabToolResult(text: "There are no notes.", ok: true) }
        let count = min(max(limit, 1), LabToolbox.listLimit)
        let dates = formatter("d MMMM yyyy HH:mm")
        var lines = notes.prefix(count).map { note in
            "id \(note.id) | \(dates.string(from: note.createdAt)) | \(String(note.title.prefix(80)))"
        }
        if notes.count > count { lines.append("\(notes.count - count) older notes are not listed.") }
        return LabToolResult(text: lines.joined(separator: "\n"), ok: true)
    }

    func readNote(id: String) -> LabToolResult {
        let wanted = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note = notes.first(where: { $0.id == wanted }) else {
            return LabToolResult(text: "There is no note with the id \(wanted).", ok: false)
        }
        guard let transcript = note.transcript, !transcript.isEmpty else {
            return LabToolResult(text: "This note has no transcript.", ok: false)
        }
        if transcript.count > LabToolbox.transcriptLimit {
            return LabToolResult(text: String(transcript.prefix(LabToolbox.transcriptLimit)) + "\nThe transcript is longer than this and was cut here.", ok: true)
        }
        return LabToolResult(text: transcript, ok: true)
    }

    /// Records a choice of screen. Nothing is shown or changed because of it.
    func chooseScreen(_ name: String) -> LabToolResult {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard LabScreen.names.contains(wanted) else {
            return LabToolResult(text: "There is no screen called \(wanted). The screens are: \(LabScreen.names.joined(separator: ", ")).", ok: false)
        }
        return LabToolResult(text: "The choice of the \(wanted) screen is recorded.", ok: true)
    }
}
