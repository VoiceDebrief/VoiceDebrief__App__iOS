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
            Tab("Record", systemImage: "mic.fill", value: RootTab.record) {
                launched(.record) { RecordView(session: session, book: book, go: { tab = $0 }) }.tracked("record")
            }
            Tab("Library", systemImage: "tray.full", value: RootTab.library) {
                launched(.library) { LibraryView(session: session, book: book) }.tracked("library")
            }
            Tab("Contacts", systemImage: "person.2", value: RootTab.contacts) {
                NavigationStack { RecipientsView() }.tracked("contacts")
            }
            Tab("Vaults", systemImage: "lock.shield", value: RootTab.vaults) {
                launched(.vaults) { VaultsView(book: book) }.tracked("vaults")
            }
            Tab("Agents", systemImage: "person.3", value: RootTab.agents) {
                AgentsView(book: book).tracked("agents")
            }
            Tab("Guide", systemImage: "book", value: RootTab.guide) {
                GuideView().tracked("guide")
            }
            TabSection("You") {
                Tab("Identity", systemImage: "person.badge.key", value: RootTab.identity) {
                    NavigationStack { IdentityView(vaults: book) }.tracked("identity")
                }
                Tab("Credit", systemImage: "sterlingsign.circle", value: RootTab.credit) {
                    NavigationStack { CreditView() }.tracked("credit")
                }
                Tab("Your activity", systemImage: "chart.bar", value: RootTab.activity) {
                    NavigationStack { ActivityView() }.tracked("activity")
                }
            }
            TabSection("Experiments") {
                Tab("Lab", systemImage: "flask", value: RootTab.lab) {
                    NavigationStack { LabView(store: session.store) }.tracked("lab")
                }
                Tab("Your words", systemImage: "character.book.closed", value: RootTab.words) {
                    NavigationStack { GlossaryView() }.tracked("words")
                }
            }
            TabSection("More") {
                Tab("What this build does", systemImage: "checklist", value: RootTab.about) {
                    NavigationStack { StatusView() }.tracked("about")
                }
                Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                    launched(.settings) { SettingsView(session: session, book: book) }.tracked("settings")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .welcomeOnFirstLaunch()
        // Talk to Claude from every screen but Record, which has its own control.
        .overlay(alignment: .bottomTrailing) {
            if tab != .record { TalkButton(session: session) }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) { LaunchMarker() }
        #endif
        .task {
            // A Talk to Claude recording cannot survive a relaunch; do not let its flag outlive it.
            UserDefaults.standard.set(false, forKey: "vd.talking")
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
