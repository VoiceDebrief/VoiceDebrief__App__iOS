import SwiftUI

struct RootView: View {
    @State private var store: NoteStore
    @State private var session: DebriefSession
    @State private var book = VaultBook()

    init() {
        let store = NoteStore()
        _store = State(initialValue: store)
        _session = State(initialValue: DebriefSession(store: store))
    }

    var body: some View {
        TabView {
            Tab("Record", systemImage: "mic") {
                RecordView(session: session, book: book)
            }
            Tab("Library", systemImage: "tray.full") {
                LibraryView(session: session, book: book)
            }
            Tab("Vaults", systemImage: "lock.shield") {
                VaultsView(book: book)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(session: session, book: book)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
