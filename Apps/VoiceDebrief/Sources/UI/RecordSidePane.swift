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
            // A newer build waiting in TestFlight, said where the eyes are (the owner: "a button here that says
            // update to the new version").
            if let latest = desk.report?.latestBuild, AppInfo.isNewer(latest, than: AppInfo.version()) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
                    Text("v\(latest) is ready (you have v\(AppInfo.version()))").font(.subheadline.weight(.semibold))
                    Spacer()
                    Link("Update", destination: AppInfo.testFlight).buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
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

/// Who works for you, by topic (the owner, 16 November 2026: "put them on separate tabs... all the waiting for
/// input in one place, so I can act on them... the drawing doesn't make sense, it should be alive"). A row of
/// sub-tabs: Waiting for input first (every agent that waits, from every project), then one per project, each
/// with its count. Tap an agent for its details and a box to write to it: the message goes to Claude, the
/// conductor, which passes it on. The counts are live from the report; nothing is drawn ahead of time.
private struct AgentsTab: View {
    private var desk: AgentsDesk { AgentsDesk.shared }
    @AppStorage("vd.pane.agentsTopic") private var topic = AgentsTab.waiting
    @State private var open: AgentsReport.Agent?
    static let waiting = "Waiting for input"

    private static func isWaiting(_ a: AgentsReport.Agent) -> Bool { a.status == "waiting" || a.status == "blocked" }

    var body: some View {
        let agents = desk.report?.agents ?? []
        let groups = Dictionary(grouping: agents) { $0.group ?? "VoiceDebrief" }
        let order = groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
        let waitingAll = agents.filter(Self.isWaiting)
        let shown: [AgentsReport.Agent] = topic == Self.waiting ? waitingAll : (groups[topic] ?? [])
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if agents.isEmpty {
                Text(desk.vaultId.isEmpty ? "Give Claude a vault on the Agents screen to see the agents working for you."
                                          : "No agents reported yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: DS.Space.m) {
                    stat(agents.filter { $0.status == "working" }.count, "working", .green)
                    stat(waitingAll.count, "waiting", .orange)
                    stat(agents.count, "in all", .secondary)
                    Spacer()
                    if let made = desk.report?.made {
                        Text("as of \(made.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip(Self.waiting, count: waitingAll.count, tint: .orange)
                        ForEach(order, id: \.self) { name in chip(name, count: groups[name]?.count ?? 0, tint: .accentColor) }
                    }
                }
                if shown.isEmpty {
                    Text(topic == Self.waiting ? "Nobody is waiting for you." : "No agents here.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(shown.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }) { agent in
                        Button { open = agent } label: { row(agent, showGroup: topic == Self.waiting) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .sheet(item: $open) { agent in
            NavigationStack { AgentDetail(agent: agent) }
        }
    }

    private func stat(_ n: Int, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chip(_ name: String, count: Int, tint: Color) -> some View {
        let selected = topic == name
        return Button { topic = name } label: {
            HStack(spacing: 5) {
                Text(name)
                Text("\(count)").font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(tint.opacity(0.2), in: Capsule())
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? tint.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(selected ? tint : .primary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ agent: AgentsReport.Agent, showGroup: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(AgentDetail.colour(agent.status)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(agent.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let at = agent.lastActive {
                        Text(at.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if showGroup, let group = agent.group {
                    Text(group).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                Text(agent.doing).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// One agent: what it is, what it is doing, what it waits for, and a box to write to it. The message goes
/// to Claude (the conductor) sealed, which passes it on to that agent.
struct AgentDetail: View {
    let agent: AgentsReport.Agent
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sentAt: Date?
    private var desk: AgentsDesk { AgentsDesk.shared }

    static func colour(_ status: String) -> Color {
        switch status {
        case "working": .green
        case "waiting", "blocked": .orange
        case "done": .blue
        default: .secondary
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(agent.status.capitalized, systemImage: "circle.fill").foregroundStyle(Self.colour(agent.status))
                }
                if let group = agent.group { LabeledContent("Project", value: group) }
                if let at = agent.lastActive {
                    LabeledContent("Last moved", value: at.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("What it does") { Text(agent.role) }
            Section("Doing now") { Text(agent.doing) }
            if let waiting = agent.waitingFor {
                Section("Waiting for") { Text(waiting).foregroundStyle(.orange) }
            }
            Section {
                TextField("Write to \(agent.name)", text: $draft, axis: .vertical)
                    .lineLimit(3...8)
                    .voiceInput($draft)
                Button {
                    let text = draft
                    Task {
                        await desk.send(text, to: agent)
                        if desk.problem == nil { draft = ""; sentAt = Date() }
                    }
                } label: {
                    Label(desk.sending ? "Sending" : "Send", systemImage: "paperplane.fill")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || desk.sending)
            } header: {
                Text("Write to it")
            } footer: {
                if let sentAt {
                    Text("Sent \(sentAt.formatted(date: .omitted, time: .shortened)) to Claude, who passes it on. The answer comes back in Updates.")
                } else if let problem = desk.problem {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text("Your message goes to Claude, sealed, and Claude passes it on to this agent.")
                }
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
