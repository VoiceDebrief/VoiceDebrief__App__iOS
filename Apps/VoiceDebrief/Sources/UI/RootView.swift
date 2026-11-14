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
        // Every part of the app in plain sight (the owner, 14 November 2026: "every feature should be
        // visible and linked, not hidden away"). A sidebar on iPad and Mac; on iPhone the first four are
        // tabs and the rest are under More.
        TabView(selection: $tab) {
            Tab(RootTab.record.title, systemImage: RootTab.record.symbol, value: RootTab.record) {
                launched(.record) { RecordView(session: session, book: book, go: { tab = $0 }) }.tracked("record")
            }
            Tab(RootTab.library.title, systemImage: RootTab.library.symbol, value: RootTab.library) {
                launched(.library) { LibraryView(session: session, book: book) }.tracked("library")
            }
            Tab(RootTab.contacts.title, systemImage: RootTab.contacts.symbol, value: RootTab.contacts) {
                NavigationStack { RecipientsView() }.tracked("contacts")
            }
            Tab(RootTab.vaults.title, systemImage: RootTab.vaults.symbol, value: RootTab.vaults) {
                launched(.vaults) { VaultsView(book: book) }.tracked("vaults")
            }
            TabSection("You") {
                Tab(RootTab.identity.title, systemImage: RootTab.identity.symbol, value: RootTab.identity) {
                    NavigationStack { IdentityView(vaults: book) }.tracked("identity")
                }
                Tab(RootTab.credit.title, systemImage: RootTab.credit.symbol, value: RootTab.credit) {
                    NavigationStack { CreditView() }.tracked("credit")
                }
                Tab(RootTab.activity.title, systemImage: RootTab.activity.symbol, value: RootTab.activity) {
                    NavigationStack { ActivityView() }.tracked("activity")
                }
            }
            TabSection("Experiments") {
                Tab(RootTab.lab.title, systemImage: RootTab.lab.symbol, value: RootTab.lab) {
                    NavigationStack { LabView(store: session.store) }.tracked("lab")
                }
                Tab(RootTab.words.title, systemImage: RootTab.words.symbol, value: RootTab.words) {
                    NavigationStack { GlossaryView() }.tracked("words")
                }
            }
            TabSection("More") {
                Tab(RootTab.about.title, systemImage: RootTab.about.symbol, value: RootTab.about) {
                    NavigationStack { StatusView() }.tracked("about")
                }
                Tab(RootTab.settings.title, systemImage: RootTab.settings.symbol, value: RootTab.settings) {
                    launched(.settings) { SettingsView(session: session, book: book) }.tracked("settings")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if DEBUG
        .overlay(alignment: .topLeading) { LaunchMarker() }
        #endif
        .task {
            // Finishing a note saves it to the chosen vault, unless that is switched off (issue 022).
            session.onNoteReady = { [store, book] id in
                Task { await AutoSave.run(noteId: id, store: store, book: book) }
            }
        }
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
