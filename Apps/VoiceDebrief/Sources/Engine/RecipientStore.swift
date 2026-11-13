import Foundation
import Observation

/// The recipients this device knows, kept as one JSON file. The lane built into the test build is
/// always first and cannot be removed here.
@MainActor
@Observable
final class RecipientStore {
    // Seam for the screenshots (issue 016, work/screens): a launch with -VDSampleData (debug builds
    // only) keeps this in the sample's temporary folder, never in the real file.
    static let shared: RecipientStore = {
        if let file = LaunchOptions.sampleFile("recipients.json") { return RecipientStore(file: file) }
        return RecipientStore()
    }()
    static let builtInName = "The developer"

    let file: URL
    private(set) var added: [Recipient] = []

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "recipients.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Recipient].self, from: data) {
            added = saved.filter { $0.lane != nil && $0.link != DeveloperLane.builtInLink }
        }
    }

    var builtIn: Recipient? {
        DeveloperLane.builtIn == nil ? nil : Recipient(name: Self.builtInName, link: DeveloperLane.builtInLink)
    }

    var all: [Recipient] { (builtIn.map { [$0] } ?? []) + added }

    func isBuiltIn(_ recipient: Recipient) -> Bool { recipient.link == DeveloperLane.builtInLink }

    /// True if the text held a lane link and it is now a recipient.
    @discardableResult
    func add(name: String, text: String) -> Bool {
        guard let found = RecipientLink.read(text), found.link != DeveloperLane.builtInLink else { return false }
        added = RecipientLink.adding(name: name.isEmpty ? found.name : name, link: found.link, to: added)
        write()
        return true
    }

    func remove(_ recipient: Recipient) {
        added.removeAll { $0.link == recipient.link }
        write()
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(added).write(to: file, options: .atomic)
    }
}
