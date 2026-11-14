import SwiftUI

/// The Guide: one place to find out what exists, what changed and what is coming, for the owner, a new
/// tester and a teammate alike (the owner's request of 14 November 2026: "I wake up and I go, okay, what
/// has been created?"). It holds What is new, the Ideas tracker and, as they are written, a guide per
/// feature. Content comes from the bundled data; nothing on these screens is decided here.
struct GuideView: View {
    private let ideas = IdeaBook.bundled()
    private let history = VersionHistory.bundled()
    private let guides = GuideBook.bundled()
    private let current = AppInfo.shortVersion()
    @AppStorage(WhatsNewMemory.key) private var lastSeen = ""

    var body: some View {
        NavigationStack {
            GuideHome(ideas: ideas, history: history, guides: guides, current: current, lastSeen: lastSeen)
                .onAppear { WhatsNewMemory.seedIfNeeded(current: current) }
        }
    }
}

/// The Guide's first screen, without its navigation stack, so it can also be pushed from another screen.
struct GuideHome: View {
    let ideas: IdeaBook?
    let history: VersionHistory?
    let guides: GuideBook?
    let current: String
    let lastSeen: String

    var body: some View {
        let unseen = history?.since(lastSeen, current: current) ?? []
        let latest = history?.all(current: current).first
        List {
            Section {
                Text("What this app does, what changed, and every idea with where it stands.")
                    .foregroundStyle(.secondary)
            }

            Section("What is new") {
                if let history {
                    NavigationLink {
                        WhatsNewView(history: history, current: current)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(unseen.isEmpty ? "Every version" : (unseen.count == 1 ? "1 version since you last looked" : "\(unseen.count) versions since you last looked"))
                                    .font(.body.weight(.medium))
                                if !unseen.isEmpty { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Color.accentColor) }
                            }
                            if let latest, let first = latest.notes.first {
                                Text("\(latest.version): \(first)").font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                } else {
                    Text("This build carries no release notes.").foregroundStyle(.secondary)
                }
            }

            Section("How to use it") {
                if let guides, !guides.guides.isEmpty {
                    ForEach(guides.guides) { g in
                        NavigationLink { FeatureGuideView(guide: g, ideas: ideas, pictures: guides.pictures) } label: {
                            Label(g.title, systemImage: "book.pages")
                        }
                    }
                } else {
                    Text("This build carries no feature guides.").foregroundStyle(.secondary)
                }
            }

            Section {
                if let ideas {
                    NavigationLink { IdeasView(book: ideas) } label: {
                        Label("Every idea (\(ideas.ideas.count))", systemImage: "lightbulb")
                    }
                    ForEach(ideas.statuses) { s in
                        NavigationLink { IdeasView(book: ideas, status: s.id) } label: {
                            HStack {
                                Label(s.label, systemImage: IdeaStyle.symbol(s.id)).foregroundStyle(IdeaStyle.tint(s.id))
                                Spacer()
                                Text("\(ideas.counts[s.id] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } else {
                    Text("This build carries no list of ideas.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Ideas and where they stand")
            } footer: {
                Text("From the project's issues, articles and reality files, as they were when this build was made.")
            }

            Section("On the web") {
                Link(destination: AppInfo.site.appendingPathComponent("ideas/index.html")) {
                    Label("Ideas, on the project's site", systemImage: "globe")
                }
                Link(destination: AppInfo.site.appendingPathComponent("built/index.html")) {
                    Label("What is built", systemImage: "checklist")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Guide")
    }
}
