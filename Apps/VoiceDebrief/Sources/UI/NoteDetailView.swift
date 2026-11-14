import SwiftUI

/// One note. It opens the moment a recording stops and fills in as the transcript and the debrief
/// arrive; later it is how a note in the library is read.
struct NoteDetailView: View {
    let noteId: String
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var confirmingDelete = false
    @State private var player = NotePlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let note = session.store.note(noteId) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        // The gist first: the debrief's one sentence is the heading, the date beneath it.
                        if let gist = oneSentence(note) {
                            Text(gist)
                                .font(.title3.weight(.semibold))
                                .textSelection(.enabled)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + meta(note))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.title3.weight(.semibold))
                            Text(meta(note))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let working = session.workingText(for: noteId) {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(working)
                        }
                    } else if note.processing {
                        Label("This note was interrupted before it finished. The recording is kept.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    } else {
                        Label("Kept on this device", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let last = note.saves?.last {
                            Label("Saved to the vault \(last.vaultName), \(last.at.formatted(date: .omitted, time: .shortened))", systemImage: "lock.doc.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let why = note.saveProblem {
                            Label("Not saved to a vault: \(why)", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let problem = session.store.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    }
                }

                if let url = session.store.audioURL(for: noteId), session.workingText(for: noteId) == nil, !isRecording(noteId) {
                    PlayerSection(url: url, player: player)
                }

                RunSections(run: note.run, oneSentenceShown: oneSentence(note) != nil,
                            onLine: session.store.audioURL(for: noteId) == nil ? nil : { player.play(fromMs: $0) })

                if let transcript = note.run.transcript, !transcript.isEmpty, session.workingText(for: noteId) == nil {
                    CleanTextSection(note: note, store: session.store)
                }

                if note.run.transcript != nil, !note.processing || session.workingText(for: noteId) == nil {
                    SaveToVaultSection(note: note, audioURL: session.store.audioURL(for: noteId), book: book)
                }

                Section {
                    Button(note.run.transcript == nil ? "Transcribe and debrief" : "Transcribe and debrief again") {
                        session.reprocess(noteId, localeId: localeId)
                    }
                    .disabled(session.isBusy || localeId.isEmpty)
                    Button("Delete from this device", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(session.workingText(for: noteId) != nil)
                } footer: {
                    Text("Running it again uses the language chosen now (\(localeId.isEmpty ? "none" : LocaleNames.name(localeId))) and replaces this note's transcript and debrief.")
                }
            }
            .readableWidth()
            .safeAreaInset(edge: .bottom) {
                if offersSend(note) { SendBar(noteId: noteId, session: session) }
            }
            .navigationTitle("Note")
            .task(id: noteId) {
                // Opening a finished note to read it is charged, once in a session. A note that opens
                // itself while it is still being made is not.
                if !note.processing, session.workingText(for: noteId) == nil {
                    CreditLedger.shared.chargeOnce(.readNote, noteId: noteId)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { player.stop() }
            .alert("Delete this note from this device?", isPresented: $confirmingDelete) {
                Button("Delete the note and its recording", role: .destructive) {
                    session.store.delete(noteId)
                    CreditLedger.shared.charge(.deleteNote, noteId: noteId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A copy saved to a vault stays in the vault.")
            }
        } else {
            ContentUnavailableView("This note is no longer on this device", systemImage: "tray")
        }
    }

    private func isRecording(_ id: String) -> Bool { session.recordingNote == id }

    private func oneSentence(_ note: Note) -> String? {
        note.run.debrief.flatMap { Note.oneSentence(in: $0) }
    }

    /// The send bar is for a note being made (sent the moment it is ready) or a finished one with
    /// words in it; not for one that was interrupted or has no transcript (review round 1, issue 031).
    private func offersSend(_ note: Note) -> Bool {
        if session.workingText(for: noteId) != nil { return true }
        return !note.processing && note.run.transcript?.isEmpty == false
    }

    private func meta(_ note: Note) -> String {
        var parts: [String] = []
        if let seconds = note.run.audioSeconds { parts.append(Timecode.duration(seconds: seconds)) }
        parts.append(LocaleNames.name(note.run.localeId))
        parts.append(note.run.source)
        return parts.joined(separator: " · ")
    }
}
