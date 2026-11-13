import SwiftUI

/// Every note kept on this device, newest first, by day.
struct LibraryView: View {
    let session: DebriefSession
    let book: VaultBook

    var body: some View {
        NavigationStack {
            List {
                ForEach(NoteGrouping.byDay(session.store.notes), id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.notes) { note in
                            NavigationLink(value: note.id) {
                                NoteRow(note: note, working: session.workingText(for: note.id))
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets where session.workingText(for: group.notes[index].id) == nil {
                                session.store.delete(group.notes[index].id)
                            }
                        }
                    }
                }
            }
            .overlay {
                if session.store.notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "tray",
                                           description: Text("A note is kept here the moment its recording stops."))
                }
            }
            .navigationTitle("Library")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CreditCounter() } }
            .navigationDestination(for: String.self) { id in
                NoteDetailView(noteId: id, session: session, book: book)
            }
        }
    }
}
