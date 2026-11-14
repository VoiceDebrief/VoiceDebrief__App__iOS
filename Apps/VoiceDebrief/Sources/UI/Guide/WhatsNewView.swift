import SwiftUI

/// Where the Guide remembers the last version a person looked at in What is new.
enum WhatsNewMemory {
    static let key = "vd.guide.lastSeenVersion"

    /// Called once at launch: on the first launch that has the Guide, remember this version as seen, so
    /// that the next update can say what changed since. Never overwrites what a person has seen.
    static func seedIfNeeded(current: String = AppInfo.shortVersion(), defaults: UserDefaults = .standard) {
        if (defaults.string(forKey: key) ?? "").isEmpty { defaults.set(current, forKey: key) }
    }

    /// The versions not yet looked at, for a badge or the briefing card.
    static func unseen(in history: VersionHistory?, current: String = AppInfo.shortVersion(), defaults: UserDefaults = .standard) -> [VersionEntry] {
        history?.since(defaults.string(forKey: key), current: current) ?? []
    }
}

/// What changed, version by version, newest first, with the versions not yet looked at marked "since you
/// last looked" (issue 025). From vd-versions.json; each version links to its own page, with pictures.
struct WhatsNewView: View {
    let history: VersionHistory
    var current: String = AppInfo.shortVersion()
    @AppStorage(WhatsNewMemory.key) private var lastSeen = ""
    /// What was unseen when the screen opened: kept while it is open, though opening it marks all as seen.
    @State private var unseen: Set<String>?

    var body: some View {
        let all = history.all(current: current)
        let fresh = unseen ?? Set(history.since(lastSeen, current: current).map(\.version))
        List {
            if !fresh.isEmpty {
                Section {
                    Text(fresh.count == 1 ? "1 version since you last looked." : "\(fresh.count) versions since you last looked.")
                        .font(.headline)
                }
            }
            ForEach(all) { v in
                Section {
                    ForEach(Array(v.notes.enumerated()), id: \.offset) { Text($0.element).textSelection(.enabled) }
                    if let url = URL(string: v.url) {
                        Link(destination: url) {
                            Label(v.pictures > 0 ? "Its page, with \(v.pictures) pictures" : (v.hasPage ? "Its page" : "The release history"),
                                  systemImage: "arrow.up.right.square")
                        }
                    }
                } header: {
                    HStack {
                        Text(v.version).font(.headline)
                        if v.version == current { Text("this build").font(.caption).foregroundStyle(.secondary) }
                        if fresh.contains(v.version) {
                            Text("New").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
                        }
                        Spacer()
                        Text(v.date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .readableWidth()
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No release notes in this build", systemImage: "shippingbox",
                                       description: Text("Every version's notes are on the project's site."))
            }
        }
        .navigationTitle("What is new")
        .onAppear {
            if unseen == nil { unseen = fresh }
            lastSeen = current
        }
    }
}
