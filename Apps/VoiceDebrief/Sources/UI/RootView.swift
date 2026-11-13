import SwiftUI

struct RootView: View {
    @State private var store: NoteStore
    @State private var session: DebriefSession
    @State private var book: VaultBook
    @State private var tab: RootTab

    init() {
        #if DEBUG
        // Screenshots only (issue 016): launched with -VDSampleData, the app is given invented notes
        // in a temporary folder and a vault book in memory, never the real library or Keychain.
        if let sample = SampleWorld.launched {
            _store = State(initialValue: sample.store)
            _session = State(initialValue: sample.session)
            _book = State(initialValue: sample.book)
            _tab = State(initialValue: sample.screen.tab)
            return
        }
        #endif
        let store = NoteStore()
        _store = State(initialValue: store)
        _session = State(initialValue: DebriefSession(store: store))
        _book = State(initialValue: VaultBook())
        _tab = State(initialValue: .record)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Record", systemImage: "mic", value: RootTab.record) {
                launched(.record) { RecordView(session: session, book: book) }
            }
            Tab("Library", systemImage: "tray.full", value: RootTab.library) {
                launched(.library) { LibraryView(session: session, book: book) }
            }
            Tab("Vaults", systemImage: "lock.shield", value: RootTab.vaults) {
                launched(.vaults) { VaultsView(book: book) }
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                launched(.settings) { SettingsView(session: session, book: book) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if DEBUG
        .overlay(alignment: .topLeading) { LaunchMarker() }
        #endif
    }

    /// A tab's own first screen, or, in a sample launch that names a screen reached by a tap from
    /// it, that screen (see `LaunchedScreen`).
    @ViewBuilder
    private func launched<Real: View>(_ tab: RootTab, @ViewBuilder real: () -> Real) -> some View {
        #if DEBUG
        if let sample = SampleWorld.launched, sample.screen.tab == tab, sample.screen.isPushed {
            LaunchedScreen(sample: sample)
        } else {
            real()
        }
        #else
        real()
        #endif
    }
}
