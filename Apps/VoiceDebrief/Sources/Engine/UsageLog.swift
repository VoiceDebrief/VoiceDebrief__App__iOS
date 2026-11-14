import Foundation
import Observation
import SwiftUI

/// What happens in the app, kept on this device: every screen opened and for how long, and the main
/// actions (the owner's request, 14 November 2026: "capture every single thing that happens on the app,
/// a metric for every page ... and an option to send it to you"). Never the words of a note, a name
/// or a key: screen ids, action ids and times only.
@MainActor
@Observable
final class UsageLog {
    static let shared = UsageLog()
    static let limit = 5000

    struct Event: Codable, Equatable, Sendable {
        let at: Date
        let kind: String        // "screen" or "action"
        let name: String        // "record", "library", "record.start", "note.send" ...
        var seconds: Double?    // for a screen: how long it was open
    }

    let file: URL
    private(set) var events: [Event] = []

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "usage.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = (try? decoder.decode([Event].self, from: data)) ?? []
        }
    }

    func screen(_ name: String, seconds: Double) { append(Event(at: Date(), kind: "screen", name: name, seconds: seconds)) }
    func action(_ name: String) { append(Event(at: Date(), kind: "action", name: name, seconds: nil)) }

    var lastUsed: Date? { events.last?.at }

    /// Per screen: how many times opened and the time spent; per action: how many times.
    var screens: [(name: String, count: Int, seconds: Double)] {
        Dictionary(grouping: events.filter { $0.kind == "screen" }, by: \.name)
            .map { ($0.key, $0.value.count, $0.value.compactMap(\.seconds).reduce(0, +)) }
            .sorted { $0.count > $1.count }
    }
    var actions: [(name: String, count: Int)] {
        Dictionary(grouping: events.filter { $0.kind == "action" }, by: \.name)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    /// The report sent to the developer: the counts and the events, no content.
    func report(app: String, device: String) throws -> Data {
        struct Report: Encodable {
            let app: String; let device: String; let made: Date; let events: [Event]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Report(app: app, device: device, made: Date(), events: events))
    }

    func clear() { events = []; write() }

    private func append(_ event: Event) {
        events.append(event)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
        write()
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(events).write(to: file, options: .atomic)
    }
}

/// Records how long a screen was open.
private struct Tracked: ViewModifier {
    let name: String
    @State private var since: Date?
    func body(content: Content) -> some View {
        content
            .onAppear { since = Date() }
            .onDisappear {
                if let since { UsageLog.shared.screen(name, seconds: Date().timeIntervalSince(since)) }
                since = nil
            }
    }
}

extension View {
    func tracked(_ screen: String) -> some View { modifier(Tracked(name: screen)) }
}
