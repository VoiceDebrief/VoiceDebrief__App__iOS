#if DEBUG
import Foundation
import SGitVault
import SwiftUI

/// Everything the app is given instead of the real library and Keychain when it is launched with
/// `-VDSampleData` (issue 016): a `NoteStore` in a temporary folder holding invented notes, a
/// `VaultBook` over a `MemoryStore` whose vaults live in the same temporary folder, and, in the full
/// set, one invented vault and one invented server. The vault is made by the book itself, as the
/// app makes one: on this device, with no network. The network is switched off for the whole
/// launch (`SampleNetwork`): every request fails as if the device were offline.
/// The recipients, the glossary and the credit ledger are stores of their own; in a sample launch
/// each keeps its file in the same temporary folder (`LaunchOptions.sampleFile`). Not replaced:
/// the settings in UserDefaults (the language, the vault chosen for saving).
/// A new launch starts again from nothing. Not compiled into a release build.
@MainActor
final class SampleWorld {
    /// The world this launch asked for, or nil for a normal launch. Made once.
    static let launched: SampleWorld? = {
        guard let set = LaunchOptions.sampleSet() else { return nil }
        let world = SampleWorld(set: set, screen: LaunchOptions.screen() ?? .record, root: LaunchOptions.sampleRoot)
        SampleNetwork.start()
        world.preparing = Task { await world.prepareVault() }
        return world
    }()

    let set: SampleSet
    let screen: LaunchScreen
    let root: URL
    let store: NoteStore
    let session: DebriefSession
    let book: VaultBook
    /// The id each invented note was given in the store.
    let noteIds: [SampleData.Kind: String]
    /// The invented vault, once `prepareVault` has made it (full set only).
    var vault: SavedVault? { book.vaults.first }
    private(set) var vaultProblem: String?
    private var preparing: Task<Void, Never>?

    init(set: SampleSet, screen: LaunchScreen, now: Date = Date(),
         root: URL = FileManager.default.temporaryDirectory
            .appending(path: "vd-sample-\(UUID().uuidString)", directoryHint: .isDirectory)) {
        let store = NoteStore(root: root.appending(path: "notes", directoryHint: .isDirectory))
        let session = DebriefSession(store: store)

        // Oldest first: the store puts each new note at the top, as it does for a real recording.
        var ids: [SampleData.Kind: String] = [:]
        for sample in SampleData.notes(for: screen, set: set) {
            guard let made = store.begin(source: sample.run.source, localeId: sample.run.localeId,
                                         now: now.addingTimeInterval(-sample.secondsAgo)) else { continue }
            try? SampleData.silence(seconds: sample.recordedSeconds).write(to: made.audio)
            store.update(made.note.id, run: sample.run, processing: sample.processing)
            ids[sample.kind] = made.note.id
        }

        if set == .full {
            switch screen {
            case .recordRecording:
                session.showSample(phase: .recording(since: now.addingTimeInterval(-SampleData.recordingSeconds)),
                                   liveSettled: SampleData.liveSettled, liveVolatile: SampleData.liveVolatile,
                                   levels: SampleData.levels)
            case .library, .recordWorking, .noteWorking, .noteQueued:
                session.showSample(phase: .working("Writing the debrief"), noteId: ids[.working])
                // Send pressed before the note is finished: it waits. Nothing is sent, now or later.
                if screen == .noteQueued, let id = ids[.working], let recipient = RecipientStore.shared.builtIn {
                    session.send(noteId: id, to: recipient)
                }
            default:
                break
            }
        }

        // Vaults live in the temporary folder, their keys in memory. The server is invented and
        // never reached; its token is not a token, it only makes the screens show one is held.
        let book = VaultBook(store: MemoryStore(), localRoot: root.appending(path: "vaults", directoryHint: .isDirectory),
                             cacheRoot: root.appending(path: "vault-cache", directoryHint: .isDirectory))
        if set == .full {
            book.addRemote(name: SampleData.serverName, address: SampleData.serverAddress, token: "invented-sample-token")
        }

        self.set = set
        self.screen = screen
        self.root = root
        self.store = store
        self.session = session
        self.book = book
        self.noteIds = ids
    }

    func noteId(for screen: LaunchScreen) -> String? {
        SampleData.kind(for: screen).flatMap { noteIds[$0] }
    }

    /// Returns once the invented vault is written (at once in the empty set).
    func prepared() async {
        await preparing?.value
    }

    /// Makes the invented vault through the book, as the Vaults screen does: created on this device,
    /// then the finished sample note saved into it as one signed commit. No request is made.
    func prepareVault() async {
        guard set == .full, book.vaults.isEmpty else { return }
        await book.create(name: SampleData.vaultName)
        guard let made = book.vaults.first else {
            vaultProblem = book.problem ?? "The sample vault was not created."
            return
        }
        do {
            let audio = noteIds[.finished].flatMap { store.audioURL(for: $0) }
            _ = try await book.save(run: SampleData.finished.run, audioURL: audio, to: made)
        } catch {
            vaultProblem = VaultBook.describe(error)
        }
    }
}

/// No network in a sample launch: every http and https request the app makes fails here as if
/// the device were offline. The sample vault is on this device and needs none.
final class SampleNetwork: URLProtocol {
    static func start() {
        URLProtocol.registerClass(SampleNetwork.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        let scheme = request.url?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

/// A screen that is reached by a tap, shown pushed on a stand-in for its tab's first screen, so
/// the picture has the real tab bar, title and back button around the real view.
struct LaunchedScreen: View {
    let sample: SampleWorld
    @State private var path: [String]

    init(sample: SampleWorld) {
        self.sample = sample
        _path = State(initialValue: LaunchedScreen.needsVault(sample.screen) ? [] : [sample.screen.rawValue])
    }

    static func needsVault(_ screen: LaunchScreen) -> Bool {
        screen == .vaultDetail || screen == .traffic
    }

    private var parentTitle: String {
        switch sample.screen.tab {
        case .record: return "VoiceDebrief"
        case .library: return "Library"
        case .vaults: return "Vaults"
        case .settings: return "Settings"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {}
                .navigationTitle(parentTitle)
                .navigationDestination(for: String.self) { _ in destination }
        }
        .task {
            guard path.isEmpty else { return }
            await sample.prepared()
            // "Every step" is shown after the vault was opened once, so it lists what opening one takes.
            if sample.screen == .traffic, let vault = sample.vault {
                _ = try? await sample.book.contents(of: vault)
            }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { path = [sample.screen.rawValue] }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch sample.screen {
        case .noteFinished, .noteTranscript, .noteInterrupted, .noteWorking, .noteQueued:
            NoteDetailView(noteId: sample.noteId(for: sample.screen) ?? "", session: sample.session, book: sample.book)
        case .vaultDetail:
            if let vault = sample.vault {
                VaultDetailView(book: sample.book, vault: vault)
            } else {
                ContentUnavailableView("The empty sample set has no vault", systemImage: "lock.shield")
            }
        case .recipients:
            RecipientsView()
        case .words:
            GlossaryView()
        case .credit:
            CreditView()
        case .identity:
            IdentityView(vaults: sample.book)
        case .lab:
            LabView(store: sample.store)
        case .labPrompt:
            LabOnePromptView(store: sample.store)
        case .diagnostics:
            DiagnosticsView(session: sample.session)
        case .traffic:
            TrafficView(log: sample.book.log)
        case .about:
            StatusView()
        default:
            EmptyView()
        }
    }
}

/// An element with no size that names the launched screen, for the UI tests.
struct LaunchMarker: View {
    var body: some View {
        if let sample = SampleWorld.launched {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Sample data")
                .accessibilityIdentifier(sample.screen.marker)
                .allowsHitTesting(false)
        }
    }
}
#endif
