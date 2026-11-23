import SwiftUI

/// On an iPhone, the tab bar holds Record, Library, Contacts, Vaults and More; More is this list of
/// every other part of the app, grouped as the sidebar groups them. Choosing one selects its tab, so
/// each part keeps its own navigation and shows one back button, not two (the system's More put a
/// second navigation bar above each part's own: seen in the screens session's pictures).
struct MoreHubView: View {
    let go: (RootTab) -> Void

    struct Group: Identifiable {
        let title: String?
        let tabs: [RootTab]
        var id: String { title ?? "top" }
    }

    /// The sidebar's order and sections, past the four in the tab bar.
    static let groups: [Group] = [
        Group(title: nil, tabs: [.inbox, .agents, .play, .guide]),
        Group(title: "You", tabs: [.owner, .identity, .credit, .activity]),
        Group(title: "Experiments", tabs: [.lab, .words]),
        Group(title: "More", tabs: [.about, .settings]),
    ]

    /// Every tab the hub opens: these are hidden from the iPhone tab bar.
    static var tabs: [RootTab] { groups.flatMap(\.tabs) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.groups) { group in
                    Section {
                        ForEach(group.tabs) { tab in
                            Button {
                                UsageLog.shared.action("more.\(tab.rawValue)")
                                go(tab)
                            } label: {
                                HStack(spacing: DS.Space.s) {
                                    SectionIcon(tab: tab, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tab.title).foregroundStyle(.primary)
                                        Text(tab.line).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: DS.Space.xs)
                                    Image(systemName: Icon.open)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}
