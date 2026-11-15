import SwiftUI
import UIKit

/// The right of the record screen on an iPad or a Mac, as tabs, each with a count of what is new since you
/// last opened it (the owner, 15 November 2026: "multiple tabs... a counter at the top... you could already
/// be sending me updates to that vault from all the work that's happening; a visualization of the agents").
/// Live: memos to Claude and their answers. Updates: what Claude sends unasked, by stream. Agents: who works
/// for you, grouped by project. Notes: your recent notes and the rest of the app.
/// Everything comes from the agents vault you gave Claude, which only your devices and Claude can open:
/// another person using the app sees none of it. While on screen, it reads that vault every ten seconds.
struct RecordSidePane<Notes: View>: View {
    let session: DebriefSession
    let book: VaultBook
    @ViewBuilder var notes: Notes

    enum Tab: String, CaseIterable, Identifiable {
        case live, updates, agents, notes
        var id: String { rawValue }
        var title: String {
            switch self {
            case .live: "Live"
            case .updates: "Updates"
            case .agents: "Agents"
            case .notes: "Notes"
            }
        }
        var symbol: String {
            switch self {
            case .live: "dot.radiowaves.left.and.right"
            case .updates: "bell.badge"
            case .agents: "person.3.sequence"
            case .notes: "waveform"
            }
        }
    }

    @AppStorage("vd.pane.tab") private var tabName = Tab.live.rawValue
    /// When each tab was last looked at, as seconds since 1970, in one string ("live=…;updates=…").
    @AppStorage("vd.pane.seen") private var seenText = ""
    private var desk: AgentsDesk { AgentsDesk.shared }
    private var tab: Tab { Tab(rawValue: tabName) ?? .live }

    private var seen: [Tab: Date] {
        var out: [Tab: Date] = [:]
        for pair in seenText.split(separator: ";") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let t = Tab(rawValue: String(parts[0])), let s = Double(parts[1]) {
                out[t] = Date(timeIntervalSince1970: s)
            }
        }
        return out
    }

    private func markSeen(_ t: Tab) {
        var all = seen
        all[t] = Date()
        seenText = all.map { "\($0.key.rawValue)=\($0.value.timeIntervalSince1970)" }.joined(separator: ";")
    }

    private var fromClaude: [AgentsReport.Message] { (desk.report?.messages ?? []).filter { $0.from != "you" } }

    /// What is new on a tab since it was last opened.
    private func count(_ t: Tab) -> Int {
        let since = seen[t] ?? .distantPast
        switch t {
        case .live: return fromClaude.filter { $0.replyTo != nil && $0.at > since }.count
        case .updates: return fromClaude.filter { $0.replyTo == nil && $0.at > since }.count
        case .agents: return (desk.report?.agents ?? []).filter { ($0.lastActive ?? .distantPast) > since }.count
        case .notes: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            tabBar
            switch tab {
            case .live: LivePanel(session: session, book: book, showsHeading: false)
            case .updates: UpdatesTab()
            case .agents: AgentsTab()
            case .notes: notes
            }
        }
        .onChange(of: tabName) { _, _ in markSeen(tab) }
        .onAppear { markSeen(tab) }
        .onDisappear { markSeen(tab) }
        .task {
            // A regular check of the vault while this column is on screen (the owner's "regular check on the lane").
            while !Task.isCancelled {
                if !desk.vaultId.isEmpty { await desk.refresh(book: book) }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(Tab.allCases) { t in
                    let n = t == tab ? 0 : count(t)
                    Button {
                        markSeen(tab)
                        tabName = t.rawValue
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.symbol)
                            Text(t.title)
                            if n > 0 {
                                Text("\(n)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .font(.subheadline.weight(t == tab ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t == tab ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground),
                                    in: Capsule())
                        .foregroundStyle(t == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n > 0 ? "\(t.title), \(n) new" : t.title)
                    .accessibilityAddTraits(t == tab ? .isSelected : [])
                }
            }
        }
    }
}

/// What Claude sends without being asked, newest first, by stream (the message's `channel`): progress on the
/// work, builds, the newsroom. With more than one stream, chips filter them.
private struct UpdatesTab: View {
    @State private var channel: String?
    private var desk: AgentsDesk { AgentsDesk.shared }

    private var updates: [AgentsReport.Message] {
        (desk.report?.messages ?? []).filter { $0.from != "you" && $0.replyTo == nil }.sorted { $0.at > $1.at }
    }

    var body: some View {
        let channels = Array(Set(updates.map { $0.channel ?? "general" })).sorted()
        let shown = updates.filter { channel == nil || ($0.channel ?? "general") == channel }
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if channels.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("All", selected: channel == nil) { channel = nil }
                        ForEach(channels, id: \.self) { c in
                            chip(c.capitalized, selected: channel == c) { channel = c }
                        }
                    }
                }
            }
            if desk.vaultId.isEmpty {
                Text("Give Claude a vault on the Agents screen, and its updates appear here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("Nothing yet. Claude posts progress here as the work happens.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown) { message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let c = message.channel {
                            Text(c.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        Text(message.at.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(message.text).font(.callout).textSelection(.enabled)
                    if let path = message.image, let data = desk.images[path], let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Who works for you, grouped by project: a count per status for each group, then each agent with what it is
/// doing and when it last moved. Above them, the conductor's drawing of the whole team when it sent one.
private struct AgentsTab: View {
    private var desk: AgentsDesk { AgentsDesk.shared }

    var body: some View {
        let agents = desk.report?.agents ?? []
        let groups = Dictionary(grouping: agents) { $0.group ?? "VoiceDebrief" }
        let order = groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if agents.isEmpty {
                Text(desk.vaultId.isEmpty ? "Give Claude a vault on the Agents screen to see the agents working for you."
                                          : "No agents reported yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(summary(agents)).font(.subheadline.weight(.semibold))
            }
            if let data = desk.picture, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(order, id: \.self) { name in
                let members = (groups[name] ?? []).sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(name).font(.headline)
                        Spacer()
                        Text(summary(members)).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(members) { agent in row(agent) }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func summary(_ agents: [AgentsReport.Agent]) -> String {
        let working = agents.filter { $0.status == "working" }.count
        let waiting = agents.filter { $0.status == "waiting" || $0.status == "blocked" }.count
        var parts = ["\(agents.count) agent\(agents.count == 1 ? "" : "s")", "\(working) working"]
        if waiting > 0 { parts.append("\(waiting) waiting") }
        return parts.joined(separator: " · ")
    }

    private func row(_ agent: AgentsReport.Agent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(colour(agent.status)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(agent.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let at = agent.lastActive {
                        Text(at.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(agent.doing).font(.caption).foregroundStyle(.secondary)
                if let waiting = agent.waitingFor {
                    Text("Waits for: \(waiting)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func colour(_ status: String) -> Color {
        switch status {
        case "working": .green
        case "waiting", "blocked": .orange
        case "done": .blue
        default: .secondary
        }
    }
}
