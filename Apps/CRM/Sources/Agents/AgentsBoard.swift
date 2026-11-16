import Foundation

/// What the agents are doing (W11): the conductor's report, arranged for a person. Groups by project,
/// the ones waiting or blocked first, who talks to whom, and what waits on you. Plain code; nothing is written.
enum AgentsBoard {
    struct Group: Identifiable, Equatable, Sendable {
        var name: String
        var agents: [AgentsReport.Agent]
        var id: String { name }
        var waiting: Int { agents.filter { $0.status == "waiting" || $0.status == "blocked" }.count }
        var working: Int { agents.filter { $0.status == "working" }.count }
    }

    /// The order a person reads them in: stuck first, then busy, then quiet.
    static func rank(_ status: String) -> Int {
        switch status {
        case "blocked": return 0
        case "waiting": return 1
        case "working": return 2
        case "idle": return 3
        case "done": return 4
        default: return 5
        }
    }

    static func groups(_ report: AgentsReport) -> [Group] {
        let byGroup = Dictionary(grouping: report.agents) { $0.group ?? "Other" }
        return byGroup.map { name, agents in
            Group(name: name, agents: agents.sorted { (rank($0.status), $0.name) < (rank($1.status), $1.name) })
        }
        .sorted { ($0.waiting > 0 ? 0 : 1, $0.name) < ($1.waiting > 0 ? 0 : 1, $1.name) }
    }

    /// Who talks to whom, by name, from the report's links.
    static func conversations(_ report: AgentsReport) -> [(from: String, to: String, label: String)] {
        let names = Dictionary(uniqueKeysWithValues: report.agents.map { ($0.id, $0.name) })
        return report.links.map { (names[$0.from] ?? $0.from, names[$0.to] ?? $0.to, $0.label) }
    }

    /// The latest messages, newest first.
    static func recent(_ report: AgentsReport, limit: Int = 20) -> [AgentsReport.Message] {
        Array(report.messages.sorted { $0.at > $1.at }.prefix(limit))
    }

    /// How long since the agent was last active, in words.
    static func since(_ date: Date?, now: Date) -> String {
        guard let date else { return "not known" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return hours < 48 ? "\(hours) h ago" : "\(hours / 24) days ago"
    }
}
