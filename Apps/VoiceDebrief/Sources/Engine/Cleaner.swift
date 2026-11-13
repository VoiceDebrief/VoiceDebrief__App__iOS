import Foundation
import Observation

/// The speaker's own words, kept on this device as one JSON file. Later it belongs in a vault, so
/// that it follows the speaker between devices.
@MainActor
@Observable
final class GlossaryStore {
    static let shared = GlossaryStore()

    let file: URL
    private(set) var terms: [GlossaryTerm] = []

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "glossary.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([GlossaryTerm].self, from: data) {
            terms = saved
        }
    }

    func add(_ word: String, heardAs: [String]) {
        terms = Glossary.adding(word, heardAs: heardAs, to: terms)
        write()
    }

    func remove(_ term: GlossaryTerm) {
        terms.removeAll { $0.id == term.id }
        write()
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(terms).write(to: file, options: .atomic)
    }
}

/// Writes a note's clean text, a passage at a time. The code owns the order and the state; the
/// model is asked one question per passage and remembers nothing between them.
@MainActor
@Observable
final class Cleaner {
    static let shared = Cleaner()

    private(set) var workingNoteId: String?
    private(set) var progress = ""

    func isWorking(on noteId: String) -> Bool { workingNoteId == noteId }

    func run(noteId: String, store: NoteStore, glossary: [GlossaryTerm]) async {
        guard workingNoteId == nil, let note = store.note(noteId), let transcript = note.run.transcript, !transcript.isEmpty else { return }
        workingNoteId = noteId
        defer {
            workingNoteId = nil
            progress = ""
        }
        var result = CleanText(passages: Passages.split(transcript.lines), madeAt: Date(),
                               glossaryWords: glossary.map(\.word), contextSize: OnDeviceModel.contextSize, finished: false)
        store.setClean(noteId, result)
        for index in result.passages.indices {
            progress = "Passage \(index + 1) of \(result.passages.count)"
            let started = Date()
            let prompt = CleanPrompt.make(heard: result.passages[index].heard, glossary: glossary, localeId: transcript.localeId)
            do {
                let made = try await OnDeviceModel.cleanPassage(prompt: prompt)
                result.passages[index].clean = made.clean.isEmpty ? nil : made.clean
                result.passages[index].questions = made.questions
                if made.clean.isEmpty { result.passages[index].problem = "The model returned nothing for this passage." }
                else { CreditLedger.shared.charge(.cleanPassage, noteId: noteId) }
            } catch {
                result.passages[index].problem = error.localizedDescription
            }
            result.passages[index].seconds = Date().timeIntervalSince(started)
            // The note may have been deleted or transcribed again while the model was thinking.
            guard store.note(noteId)?.run.transcript == transcript else { return }
            store.setClean(noteId, result)
        }
        result.finished = true
        store.setClean(noteId, result)
    }

    /// Records what the speaker said a phrase was, in the note and in the glossary.
    func answer(_ question: CleanQuestion, with answer: String, passage: CleanPassage, noteId: String,
                store: NoteStore, glossary: GlossaryStore) {
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, var clean = store.note(noteId)?.clean,
              let p = clean.passages.firstIndex(where: { $0.id == passage.id }),
              let q = clean.passages[p].questions.firstIndex(where: { $0.id == question.id }) else { return }
        clean.passages[p].questions[q].answer = answer
        store.setClean(noteId, clean)
        glossary.add(answer, heardAs: [question.phrase])
    }
}
