import SwiftUI

/// What the agents are doing (W11): read from the vault the conductor writes its report into, chosen among
/// the vault apps, and read again every 30 seconds while the screen is open. Read only.
struct AgentsView: View {
    let crm: CRMVault
    let apps: VaultApps
    @AppStorage("crm.agentsVault") private var vaultID = ""
    @State private var report: AgentsReport?
    @State private var problem: String?
    @State private var checkedAt: Date?

    private var vault: VaultApp? { apps.apps.first { $0.id == vaultID } }

    var body: some View {
        List {
            Section {
                Picker("The agents vault", selection: $vaultID) {
                    Text("None").tag("")
                    ForEach(apps.apps) { Text($0.name).tag($0.id) }
                }
                if let checkedAt { Text("Read \(AgentsBoard.since(checkedAt, now: Date()))").font(.caption).foregroundStyle(.secondary) }
                if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote) }
            } footer: {
                Text(apps.apps.isEmpty ? "Add the vault your conductor writes its report into under Vault apps first." : "The vault your conductor writes agents/agents.json into.")
            }
            if let report {
                let counts = report.counts
                Section {
                    HStack {
                        Label("\(counts.working) working", systemImage: "bolt.fill").foregroundStyle(.green)
                        Spacer()
                        Label("\(counts.waiting) waiting", systemImage: "hourglass").foregroundStyle(.orange)
                        Spacer()
                        Label("\(counts.idle) quiet", systemImage: "moon.zzz")
                    }
                    .font(.footnote)
                    Text("Written by \(report.agents.first { $0.id == report.conductor }?.name ?? report.conductor), \(AgentsBoard.since(report.made, now: Date()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let decisions = report.decisions, !decisions.isEmpty {
                    Section("Waiting on you") {
                        ForEach(decisions) { d in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title).font(.headline)
                                if let detail = d.detail { Text(detail).font(.footnote) }
                                Text(d.options.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(AgentsBoard.groups(report)) { group in
                    Section("\(group.name) · \(group.agents.count)") {
                        ForEach(group.agents) { agent in AgentRow(agent: agent) }
                    }
                }
                let talks = AgentsBoard.conversations(report)
                if !talks.isEmpty {
                    Section("Who talks to whom") {
                        ForEach(Array(talks.enumerated()), id: \.offset) { _, t in
                            Text("\(t.from) → \(t.to): \(t.label)").font(.footnote)
                        }
                    }
                }
                Section("Latest messages") {
                    ForEach(AgentsBoard.recent(report)) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.text).lineLimit(4)
                            Text("\(m.from == "you" ? "You" : m.from) · \(AgentsBoard.since(m.at, now: Date()))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if let next = report.nextSteps, !next.isEmpty {
                    Section("What happens next") { ForEach(next, id: \.self) { Text($0).font(.footnote) } }
                }
            }
        }
        .navigationTitle("Agents")
        .refreshable { await read() }
        .task(id: vaultID) {
            report = nil
            while !Task.isCancelled {
                await read()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func read() async {
        guard let vault, let key = apps.keyText(for: vault) else { return }
        do {
            report = try AgentsReport.decode(try await crm.read(path: "agents/agents.json", keyText: key))
            problem = nil
        } catch {
            problem = report == nil ? "No report from a conductor in this vault: \(error.localizedDescription)" : "Could not read it again: \(error.localizedDescription)"
        }
        checkedAt = Date()
    }
}

struct AgentRow: View {
    let agent: AgentsReport.Agent

    private var colour: Color {
        switch agent.status {
        case "working": return .green
        case "waiting", "blocked": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(colour).frame(width: 8, height: 8)
                Text(agent.name).font(.headline)
                Spacer()
                Text(agent.status).font(.caption).foregroundStyle(colour)
            }
            Text(agent.doing).font(.subheadline)
            if let waiting = agent.waitingFor { Text("Waiting for: \(waiting)").font(.caption).foregroundStyle(.orange) }
            Text("\(agent.role) · \(agent.kind) · \(AgentsBoard.since(agent.lastActive, now: Date()))").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
