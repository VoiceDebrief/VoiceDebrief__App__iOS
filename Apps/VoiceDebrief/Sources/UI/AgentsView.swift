import SwiftUI
import UIKit

/// The agents working for you: how many, doing what, waiting for what, and a conversation with each
/// (the owner, 14 November 2026). Drawn from a report the conductor writes into a vault of yours. Made
/// for a wide screen: the list on the left, the agent and its conversation on the right.
struct AgentsView: View {
    let book: VaultBook
    private let desk = AgentsDesk.shared
    @State private var selected: String?
    @State private var draft = ""
    @State private var sharing = false
    @State private var said: String?

    private var vault: SavedVault? { book.vaults.first { $0.id == desk.vaultId } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section { overview }
                if let report = desk.report {
                    Section("Agents") {
                        ForEach(report.agents) { agent in
                            AgentRow(agent: agent).tag(agent.id)
                        }
                    }
                } else {
                    Section { setup }
                }
            }
            .navigationTitle("Agents")
            .refreshable { await desk.refresh(book: book) }
            .toolbar {
                ToolbarItem { Button { Task { await desk.refresh(book: book) } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
        } detail: {
            if let report = desk.report, let id = selected, let agent = report.agents.first(where: { $0.id == id }) {
                detail(agent, report: report)
            } else if let picture = desk.picture, let image = UIImage(data: picture) {
                ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
                    .navigationTitle("Overview")
            } else {
                ContentUnavailableView("Pick an agent", systemImage: "person.3", description: Text("Its work, what it is waiting for, and your conversation with it."))
            }
        }
        .task { await desk.refresh(book: book) }
        .task {
            // While you are here, look for news every two minutes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await desk.refresh(book: book)
            }
        }
    }

    @ViewBuilder
    private var overview: some View {
        if let report = desk.report {
            let c = report.counts
            HStack(spacing: 16) {
                count(c.working, "working", .green)
                count(c.waiting, "waiting", .orange)
                count(c.idle, "idle", .secondary)
            }
            Text("Report from \(report.conductor), \(report.made.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let problem = desk.problem { Text(problem).font(.footnote).foregroundStyle(.orange) }
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack {
            Text("\(n)").font(.title.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your agents").font(.headline)
            Text("1. Choose a vault of yours that is on a server (or create one on the Vaults tab and push it).")
            Picker("Vault", selection: Binding(get: { desk.vaultId }, set: { desk.vaultId = $0 })) {
                Text("None").tag("")
                ForEach(book.vaults.filter { $0.canWrite }) { v in Text(v.name).tag(v.id) }
            }
            Text("2. Give it to Claude (developer). Its key is sealed on this device to Claude's key; the server cannot read it.")
            Button(sharing ? "Sending" : "Give this vault to Claude (developer)") {
                guard let vault else { return }
                Task {
                    sharing = true
                    defer { sharing = false }
                    do { try await desk.shareVault(vault); said = "Sent. Claude will write the first report into it shortly." }
                    catch { said = "Not sent: \(error.localizedDescription)" }
                }
            }
            .disabled(vault == nil || sharing)
            Text("3. Pull to refresh. The report appears here; nothing is invented by the app.")
            if let said { Text(said).font(.footnote).foregroundStyle(.secondary) }
        }
        .font(.callout)
    }

    private func detail(_ agent: AgentsReport.Agent, report: AgentsReport) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    LabeledContent("Role", value: agent.role)
                    LabeledContent("Status", value: agent.status)
                    Text(agent.doing)
                    if let waiting = agent.waitingFor { Label("Waiting for: \(waiting)", systemImage: "hourglass").foregroundStyle(.orange) }
                    if let last = agent.lastActive { LabeledContent("Last active", value: last.formatted(date: .abbreviated, time: .shortened)) }
                    let related = report.links.filter { $0.from == agent.id || $0.to == agent.id }
                    ForEach(Array(related.enumerated()), id: \.offset) { _, link in
                        Text("\(link.from == agent.id ? "→" : "←") \(link.from == agent.id ? link.to : link.from): \(link.label)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Conversation") {
                    let messages = desk.conversation(with: agent.id)
                    if messages.isEmpty { Text("No messages yet.").foregroundStyle(.secondary) }
                    ForEach(messages) { m in
                        HStack {
                            if m.from == "you" { Spacer(minLength: 40) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.text)
                                Text(m.at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(m.from == "you" ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            if m.from != "you" { Spacer(minLength: 40) }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
            HStack {
                TextField(agent.lane == nil ? "Message (passed on by the conductor)" : "Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = draft
                    draft = ""
                    Task { await desk.send(text, to: agent) }
                } label: { Image(systemName: "paperplane.fill") }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || desk.sending)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(agent.name)
    }
}

private struct AgentRow: View {
    let agent: AgentsReport.Agent
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).lineLimit(1)
                Text(agent.doing).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
    private var color: Color {
        switch agent.status {
        case "working": return .green
        case "waiting", "blocked": return .orange
        default: return .secondary
        }
    }
}
