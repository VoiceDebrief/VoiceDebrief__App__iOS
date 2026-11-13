#if DEBUG
import Foundation
import SGitVault
import SwiftUI

/// Everything the app is given instead of the real library and Keychain when it is launched with
/// `-VDSampleData` (issue 016): a `NoteStore` in a temporary folder holding invented notes, a
/// `VaultBook` over a `MemoryStore`, and, in the full set, one invented vault that is a real sgit
/// vault written to the same temporary folder. The network is switched off for the whole launch
/// (`SampleNetwork`): reads of the sample vault are answered from the folder, everything else fails.
/// A new launch starts again from nothing. Not compiled into a release build.
@MainActor
final class SampleWorld {
    /// The world this launch asked for, or nil for a normal launch. Made once.
    static let launched: SampleWorld? = {
        guard let set = LaunchOptions.sampleSet() else { return nil }
        let world = SampleWorld(set: set, screen: LaunchOptions.screen() ?? .record)
        SampleNetwork.start(folder: world.serverFolder)
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
    /// The invented vault, in the full set.
    let vault: SavedVault?
    private(set) var vaultProblem: String?
    private var preparing: Task<Void, Never>?

    init(set: SampleSet, screen: LaunchScreen, now: Date = Date()) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "vd-sample-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = NoteStore(root: root.appending(path: "notes", directoryHint: .isDirectory))
        let session = DebriefSession(store: store)

        // Oldest first: the store puts each new note at the top, as it does for a real recording.
        var ids: [SampleData.Kind: String] = [:]
        for sample in SampleData.notes(for: screen, set: set) {
            guard let made = store.begin(source: sample.run.source, localeId: sample.run.localeId,
                                         now: now.addingTimeInterval(-sample.secondsAgo)) else { continue }
            try? SampleData.silentWAV.write(to: made.audio)
            store.update(made.note.id, run: sample.run, processing: sample.processing)
            ids[sample.kind] = made.note.id
        }

        if set == .full {
            switch screen {
            case .recordRecording:
                session.showSample(phase: .recording(since: now.addingTimeInterval(-SampleData.recordingSeconds)),
                                   liveSettled: SampleData.liveSettled, liveVolatile: SampleData.liveVolatile,
                                   levels: SampleData.levels)
            case .library, .recordWorking, .noteWorking:
                session.showSample(phase: .working("Writing the debrief"), noteId: ids[.working])
            default:
                break
            }
        }

        // The vault's key is made at random on every launch, as the app makes a real one: there is
        // no key in the source. The token is not a token; it only makes the screens show one is held.
        let secrets = MemoryStore()
        var vault: SavedVault?
        if set == .full {
            let keyText = VaultCreate.newKeyText()
            let saved = SavedVault(id: String(keyText.split(separator: ":").last ?? ""), name: SampleData.vaultName,
                                   keyText: keyText, addedAt: now.addingTimeInterval(-3 * 86_400), createdHere: true)
            secrets.set("vaults", try? JSONEncoder().encode([saved]))
            secrets.set("access-token", Data("invented-sample-token".utf8))
            vault = saved
        }

        self.set = set
        self.screen = screen
        self.root = root
        self.store = store
        self.session = session
        self.book = VaultBook(store: secrets)
        self.noteIds = ids
        self.vault = vault
    }

    /// The folder that stands in for the vault server: `<vault id>/bare/…`, as the server holds a vault.
    var serverFolder: URL { root.appending(path: "server", directoryHint: .isDirectory) }

    func noteId(for screen: LaunchScreen) -> String? {
        SampleData.kind(for: screen).flatMap { noteIds[$0] }
    }

    /// Returns once the invented vault is written (at once in the empty set).
    func prepared() async {
        await preparing?.value
    }

    /// Writes the invented vault with the real engine: created as the app creates one, then the
    /// finished sample note saved into it as one signed commit. No request leaves the process.
    func prepareVault() async {
        guard let vault else { return }
        do {
            let signer = try book.commitSigner()
            let transport = FolderVaultTransport(root: serverFolder, perVaultSubfolder: "")
            let created = try await VaultCreate.create(keyText: vault.keyText, signer: signer, accessToken: nil, writer: transport,
                                                       timestampMs: Int64(vault.addedAt.timeIntervalSince1970 * 1000))
            guard let writeKey = created.key.writeKey else { return }
            let handle = SGitVault(address: VaultAddress(vaultId: vault.id), readKey: created.key.readKey,
                                   cache: root.appending(path: "setup-cache", directoryHint: .isDirectory),
                                   log: VaultTrafficLog(), transport: transport)
            let files = VaultBook.files(for: SampleData.finished.run, audio: SampleData.silentWAV, audioName: "audio.wav",
                                        id: "sample01", date: Date())
            let changes: [String: Data?] = Dictionary(uniqueKeysWithValues: files.map { ($0.key, Optional($0.value)) })
            _ = try await handle.commit(changes, message: "Debrief sample01", branch: "current", signer: signer,
                                        writeKey: writeKey, accessToken: nil, writer: transport)
        } catch {
            vaultProblem = VaultBook.describe(error)
        }
    }
}

/// No network in a sample launch. Every http and https request the app makes is answered here:
/// a read of the vault server's API comes from the sample folder (200, or 404 when there is no
/// such file, as the server answers), and anything else fails as if the device were offline.
final class SampleNetwork: URLProtocol {
    nonisolated(unsafe) private static var folder: URL?

    static func start(folder: URL) {
        self.folder = folder
        URLProtocol.registerClass(SampleNetwork.self)
    }

    /// The file a request reads, if it is a read of the vault server's API.
    static func file(for url: URL, in folder: URL) -> URL? {
        let prefix = "/api/vault/read/"
        let path = url.path(percentEncoded: false)
        guard url.host() == VaultAddress.defaultServer.host(), path.hasPrefix(prefix) else { return nil }
        return folder.appending(path: String(path.dropFirst(prefix.count)))
    }

    override class func canInit(with request: URLRequest) -> Bool {
        let scheme = request.url?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let folder = Self.folder, let file = Self.file(for: url, in: folder) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data = try? Data(contentsOf: file)
        let body = data ?? Data()
        guard let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Length": "\(body.count)"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
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
        case .noteFinished, .noteTranscript, .noteInterrupted, .noteWorking:
            NoteDetailView(noteId: sample.noteId(for: sample.screen) ?? "", session: sample.session, book: sample.book)
        case .vaultDetail:
            if let vault = sample.vault {
                VaultDetailView(book: sample.book, vault: vault)
            } else {
                ContentUnavailableView("The empty sample set has no vault", systemImage: "lock.shield")
            }
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
