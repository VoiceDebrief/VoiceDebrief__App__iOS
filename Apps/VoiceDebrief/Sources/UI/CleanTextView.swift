import SwiftUI

/// An experiment (issue 024), shown on a note: the note rewritten as clear sentences by Apple's
/// model, what it changed, and its questions about the parts it could not follow.
struct CleanTextSection: View {
    let note: Note
    let store: NoteStore
    private let cleaner = Cleaner.shared
    private let glossary = GlossaryStore.shared
    @State private var showingChanges = false

    private var working: Bool { cleaner.isWorking(on: note.id) }

    var body: some View {
        Section {
            if let clean = note.clean {
                if clean.passages.count > 0 {
                    Toggle("Show what was changed", isOn: $showingChanges)
                }
                ForEach(clean.passages) { passage in
                    PassageRow(passage: passage, showingChanges: showingChanges, noteId: note.id, store: store)
                }
                .listRowSeparator(.hidden)
            }
            if working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(cleaner.progress.isEmpty ? "Writing a clean text" : cleaner.progress)
                }
            } else {
                Button(note.clean == nil ? "Write a clean text" : "Write it again") {
                    let terms = glossary.terms
                    Task { await cleaner.run(noteId: note.id, store: store, glossary: terms) }
                }
                .disabled(cleaner.workingNoteId != nil || !OnDeviceModel.status.isAvailable)
                if note.clean != nil {
                    ShareLink("Share the clean text", item: note.clean?.text ?? "")
                }
            }
        } header: {
            Text("Clean text (experiment)")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if !OnDeviceModel.status.isAvailable { return OnDeviceModel.status.text }
        guard let clean = note.clean else {
            return "Rewrites the note as full sentences, a passage at a time, using your own words from Settings. Nothing is left out on purpose, and the transcript as heard is kept."
        }
        var parts = ["\(clean.passages.count) passage\(clean.passages.count == 1 ? "" : "s") in \(Timecode.duration(seconds: clean.seconds))"]
        parts.append(clean.glossaryWords.isEmpty ? "no words of yours were given to the model" : "your words given to the model: \(clean.glossaryWords.joined(separator: ", "))")
        if clean.openQuestions > 0 { parts.append("\(clean.openQuestions) question\(clean.openQuestions == 1 ? "" : "s") for you") }
        return parts.joined(separator: "; ") + ". A model wrote this: it can change what you meant. The transcript below is what was heard."
    }
}

private struct PassageRow: View {
    let passage: CleanPassage
    let showingChanges: Bool
    let noteId: String
    let store: NoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Timecode.format(ms: passage.startMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let clean = passage.clean {
                if showingChanges {
                    Text(CleanTextStyle.changes(heard: passage.heard, clean: clean))
                } else {
                    Text(clean).textSelection(.enabled)
                }
                if passage.looksCut {
                    Label("Much shorter than what was said: something may have been left out.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if let problem = passage.problem {
                Text(passage.heard).foregroundStyle(.secondary)
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text(passage.heard).foregroundStyle(.secondary)
            }
            ForEach(passage.questions) { question in
                QuestionRow(question: question, passage: passage, noteId: noteId, store: store)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct QuestionRow: View {
    let question: CleanQuestion
    let passage: CleanPassage
    let noteId: String
    let store: NoteStore
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(question.question, systemImage: "questionmark.circle.fill")
                .font(.callout.weight(.semibold))
            Text("Heard: \(question.phrase)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let given = question.answer {
                Label("You said: \(given). Kept in your words.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                HStack {
                    TextField("What you said", text: $answer)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Button("Keep") {
                        Cleaner.shared.answer(question, with: answer, passage: passage, noteId: noteId,
                                              store: store, glossary: GlossaryStore.shared)
                    }
                    .buttonStyle(.bordered)
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum CleanTextStyle {
    /// The rewrite with its changes marked: words taken out struck through, words put in green.
    static func changes(heard: String, clean: String) -> AttributedString {
        var out = AttributedString()
        for segment in WordDiff.segments(heard: heard, clean: clean) {
            var part = AttributedString(segment.text + " ")
            switch segment.kind {
            case .same:
                break
            case .removed:
                part.swiftUI.strikethroughStyle = Text.LineStyle.single
                part.swiftUI.foregroundColor = Color.secondary
            case .added:
                part.swiftUI.foregroundColor = Color.green
            }
            out += part
        }
        return out
    }
}

/// The speaker's own words: what the model is told to expect, and what the speech model tends to
/// hear in their place.
struct GlossaryView: View {
    private let glossary = GlossaryStore.shared
    @State private var word = ""
    @State private var heardAs = ""

    var body: some View {
        Form {
            Section {
                TextField("A word or name you use", text: $word)
                    .autocorrectionDisabled()
                TextField("Heard as (optional, separated by commas)", text: $heardAs)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Add") {
                    glossary.add(word, heardAs: Glossary.variants(from: heardAs, word: word))
                    word = ""
                    heardAs = ""
                }
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Apple's speech model cannot be given your words in advance, so they are given to the model that writes the clean text. Answering one of its questions adds a word here.")
            }
            Section("Your words") {
                if glossary.terms.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(glossary.terms) { term in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.word)
                        if !term.heardAs.isEmpty {
                            Text("Heard as: \(term.heardAs.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for term in offsets.map({ glossary.terms[$0] }) {
                        glossary.remove(term)
                        CreditLedger.shared.charge(.removeWord)
                    }
                }
            }
        }
        .navigationTitle("Your words")
        .navigationBarTitleDisplayMode(.inline)
    }
}
