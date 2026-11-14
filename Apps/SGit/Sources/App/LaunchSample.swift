#if DEBUG
import Observation
import SGitVault
import SwiftUI
import UIKit

/// What a UI test asks the app to show (see `UITests/ScreensTests.swift`). Debug builds only: a build
/// for TestFlight does not contain this file's code.
enum LaunchOptions {
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var screen: String? { value("-SGScreen") }
    static var sampleSet: String { value("-SGSampleData") ?? "full" }
}

/// An invented vault for the pictures: real objects, made by the real engine, in temporary folders.
/// The Keychain is in memory and the "server" is a folder, so nothing leaves the simulator.
@MainActor
@Observable
final class SampleWorld {
    let shelf: VaultShelf
    let outbox: Outbox
    private(set) var vault: SavedVault?
    private(set) var ready = false

    init() {
        let root = FileManager.default.temporaryDirectory.appending(path: "sample-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MemoryStore()
        store.set("access-token", Data("sample".utf8))
        shelf = VaultShelf(store: store, transport: FolderVaultTransport(root: root.appending(path: "server")),
                           cacheRoot: root.appending(path: "cache"), localRoot: root.appending(path: "local"))
        outbox = Outbox(root: root.appending(path: "outbox"))
    }

    func prepare(set: String) async {
        defer { ready = true }
        guard set != "empty" else { return }
        guard let made = await shelf.create(name: "Web Summit 2026") else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "sample-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var first: [IncomingFile] = []
        let pictures: [(String, String, UIColor, UIColor)] = [
            ("IMG_0412.jpg", "stage", .systemIndigo, .systemPink),
            ("IMG_0413.jpg", "stage", .systemTeal, .systemBlue),
            ("IMG_0431.jpg", "stage", .systemOrange, .systemRed),
            ("IMG_0502.jpg", "booth", .systemGreen, .systemTeal),
            ("IMG_0503.jpg", "booth", .systemYellow, .systemOrange),
            ("IMG_0611.jpg", "team/dinner", .systemPurple, .systemIndigo),
            ("IMG_0612.jpg", "team/dinner", .systemBrown, .systemYellow),
            ("Group photo.jpg", "", .systemBlue, .systemMint),
        ]
        for (name, sub, a, b) in pictures {
            let url = folder.appending(path: UUID().uuidString)
            guard (try? Self.picture(name, a, b).write(to: url)) != nil else { continue }
            first.append(IncomingFile(url: url, name: name, subfolder: sub))
        }
        for (name, sub, bytes) in [("Keynote.mov", "stage", 380_000), ("Booth walkthrough.mp4", "booth", 910_000)] {
            let url = folder.appending(path: UUID().uuidString)
            guard (try? Data(count: bytes).write(to: url)) != nil else { continue }
            first.append(IncomingFile(url: url, name: name, subfolder: sub))
        }
        if let job = try? outbox.add(first, to: made, folder: "", existing: [], shelf: shelf) { await outbox.wait(for: job.id) }
        let notes = folder.appending(path: UUID().uuidString)
        try? Data("# Who took what\n\nStage: the keynote. Booth: both days.\n".utf8).write(to: notes)
        if let job = try? outbox.add([IncomingFile(url: notes, name: "README.md")], to: made, folder: "", existing: [], shelf: shelf) {
            await outbox.wait(for: job.id)
        }
        await shelf.sendToServer(made)
        await shelf.create(name: "Drafts, not shared")
        vault = shelf.current(made)
        if let vault { _ = try? await shelf.load(vault) }
    }

    /// A picture that is plainly a sample: two colours and its own name.
    static func picture(_ name: String, _ a: UIColor, _ b: UIColor) -> Data {
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colours = [a.cgColor, b.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let text = "Sample · \(name)" as NSString
            text.draw(at: CGPoint(x: 40, y: 700), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 44),
                                                                  .foregroundColor: UIColor.white])
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

/// One screen, opened directly on the sample vault.
struct ScreenshotRoot: View {
    let screen: String
    @State private var world = SampleWorld()

    var body: some View {
        Group {
            if world.ready {
                shown
                    .overlay(alignment: .topLeading) {
                        Text("·").font(.system(size: 1)).opacity(0.02)
                            .accessibilityIdentifier("sg.screen.\(screen)")
                    }
            } else {
                ProgressView("Making the sample vault")
            }
        }
        .task {
            // The list or the grid is a stored preference: set it before the screen is made.
            UserDefaults.standard.set(screen == "vault.list", forKey: "browse.asList")
            await world.prepare(set: LaunchOptions.sampleSet)
        }
    }

    @ViewBuilder private var shown: some View {
        let shelf = world.shelf
        let outbox = world.outbox
        let files = world.vault.flatMap { shelf.contents[$0.id]?.files } ?? []
        switch (screen, world.vault) {
        case ("vaults", _):
            RootView(shelf: shelf, outbox: outbox)
        case ("create", _):
            CreateVaultSheet(shelf: shelf)
        case ("add", _):
            AddVaultSheet(shelf: shelf)
        case ("vault", let vault?):
            NavigationStack { VaultView(shelf: shelf, outbox: outbox, vault: vault, folder: "") }
        case ("vault.folder", let vault?):
            NavigationStack { VaultView(shelf: shelf, outbox: outbox, vault: vault, folder: "stage") }
        case ("vault.list", let vault?):
            NavigationStack { VaultView(shelf: shelf, outbox: outbox, vault: vault, folder: "booth") }
        case ("file", let vault?):
            if let file = files.first(where: { $0.path == "stage/IMG_0412.jpg" }) {
                NavigationStack { FileView(shelf: shelf, vault: vault, file: file) }
            }
        case ("share", let vault?):
            NavigationStack { ShareVaultView(shelf: shelf, vault: vault) }
        case ("history", let vault?):
            NavigationStack { HistoryView(shelf: shelf, vault: vault) }
        case ("commit", let vault?):
            if let commit = shelf.contents[vault.id]?.history.dropFirst().first {
                NavigationStack { CommitView(shelf: shelf, vault: vault, commit: commit) }
            }
        case ("settings", _):
            NavigationStack { SettingsView(shelf: shelf) }
        default:
            Text("No screen called \(screen)")
        }
    }
}
#endif
