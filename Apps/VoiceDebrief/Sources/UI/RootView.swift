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
        // tabs and the rest are listed by our own More tab (MoreHubView), each keeping its own navigation.
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
            Tab(RootTab.agents.title, systemImage: RootTab.agents.symbol, value: RootTab.agents) {
                AgentsView(book: book).tracked("agents")
            }
            .defaultVisibility(.hidden, for: .tabBar)
            // The games, out of the Lab and onto the sidebar (the owner: "brilliant; make them a top-level item").
            Tab(RootTab.play.title, systemImage: RootTab.play.symbol, value: RootTab.play) {
                NavigationStack { GamePlayView() }.tracked("play")
            }
            .defaultVisibility(.hidden, for: .tabBar)
            Tab(RootTab.guide.title, systemImage: RootTab.guide.symbol, value: RootTab.guide) {
                GuideView(go: { tab = $0 })
                    // Room at the bottom so the floating Talk button does not cover the last lines.
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
                    .tracked("guide")
            }
            .defaultVisibility(.hidden, for: .tabBar)
            TabSection("You") {
                Tab(RootTab.identity.title, systemImage: RootTab.identity.symbol, value: RootTab.identity) {
                    NavigationStack { IdentityView(vaults: book) }.tracked("identity")
                }
            .defaultVisibility(.hidden, for: .tabBar)
                Tab(RootTab.credit.title, systemImage: RootTab.credit.symbol, value: RootTab.credit) {
                    NavigationStack { CreditView() }.tracked("credit")
                }
            .defaultVisibility(.hidden, for: .tabBar)
                Tab(RootTab.activity.title, systemImage: RootTab.activity.symbol, value: RootTab.activity) {
                    NavigationStack { ActivityView() }.tracked("activity")
                }
            .defaultVisibility(.hidden, for: .tabBar)
            }
            TabSection("Experiments") {
                Tab(RootTab.lab.title, systemImage: RootTab.lab.symbol, value: RootTab.lab) {
                    NavigationStack { LabView(store: session.store) }.tracked("lab")
                }
            .defaultVisibility(.hidden, for: .tabBar)
                Tab(RootTab.words.title, systemImage: RootTab.words.symbol, value: RootTab.words) {
                    NavigationStack { GlossaryView() }.tracked("words")
                }
            .defaultVisibility(.hidden, for: .tabBar)
            }
            TabSection("More") {
                Tab(RootTab.about.title, systemImage: RootTab.about.symbol, value: RootTab.about) {
                    NavigationStack { StatusView() }.tracked("about")
                }
            .defaultVisibility(.hidden, for: .tabBar)
                Tab(RootTab.settings.title, systemImage: RootTab.settings.symbol, value: RootTab.settings) {
                    launched(.settings) { SettingsView(session: session, book: book) }.tracked("settings")
                }
            .defaultVisibility(.hidden, for: .tabBar)
            }
            // On an iPhone the tab bar is Record, Library, Contacts, Vaults and this list of the rest: the
            // system's own More put a second navigation bar above each part's own (two back buttons).
            Tab(RootTab.more.title, systemImage: RootTab.more.symbol, value: RootTab.more) {
                MoreHubView(go: { tab = $0 }).tracked("more")
            }
            .defaultVisibility(.hidden, for: .sidebar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .welcomeOnFirstLaunch()
        // Talk to Claude from every screen but Record, which has its own control.
        .overlay(alignment: .bottomTrailing) {
            // Not where the screen has its own microphone button (Play, the Lab) that the floating button
            // would cover (seen in the screens session's pictures, 14 November 2026).
            if ![.record, .play, .lab].contains(tab) { TalkButton(session: session, book: book) }
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
            // Lab L02 may open a section by voice (issue 047): the names are the tabs' own.
            LabActionHost.shared.sectionNames = RootTab.allCases.map(\.rawValue)
            LabActionHost.shared.openSection = { name in
                // Only the parts the Lab is told of: More is the iPhone's list, not a part of its own.
                guard let found = RootTab(rawValue: name), found != .more else { return false }
                tab = found
                return true
            }
            // Lab L02 may start a recording for a named contact, only after Do it (issue 047). The match
            // is exact, ignoring case, with "claude" for Claude (developer); anything else is refused.
            // The Lab will not listen while a voice note records (it would leave the note silent).
            LabActionHost.shared.isRecording = { [session] in session.recordingNote != nil }
            LabActionHost.shared.startRecording = { [session] spoken in
                let wanted = spoken.trimmingCharacters(in: .whitespaces).lowercased()
                let all = RecipientStore.shared.all
                let found = all.first { $0.name.lowercased() == wanted }
                    ?? (wanted == "claude" ? RecipientStore.shared.builtIn : nil)
                guard let recipient = found else {
                    let names = all.map(\.name).joined(separator: ", ")
                    return (false, "Not started: there is no contact called \(spoken)." + (names.isEmpty ? "" : " Contacts: \(names)."))
                }
                if session.recordingNote != nil { return (false, "Not started: a recording is already running.") }
                let localeId = UserDefaults.standard.string(forKey: "vd.localeId") ?? ""
                if localeId.isEmpty { return (false, "Not started: choose a language on the Record screen first.") }
                UserDefaults.standard.set(recipient.link, forKey: "vd.addressee")
                tab = .record
                await session.startRecording(localeId: localeId)
                guard session.recordingNote != nil else {
                    if case .failed(let why) = session.phase { return (false, "Not started: \(why)") }
                    return (false, "Not started: the recording could not begin.")
                }
                return (true, "Recording, for \(recipient.name) (sent when you finish).")
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
