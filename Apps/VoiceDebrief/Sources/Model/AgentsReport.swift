import Foundation

/// What the agents working for you are doing, written by the conductor agent into a vault of yours
/// (`agents/agents.json`), which only you and it can open. The app draws it; it never makes it up.
struct AgentsReport: Codable, Equatable, Sendable {
    struct Agent: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var kind: String            // "conductor", "session", "subagent"
        var role: String
        var status: String          // "working", "waiting", "idle", "blocked", "done"
        var doing: String
        var waitingFor: String?
        var parent: String?
        var lastActive: Date?
        var lane: String?           // an sgi1 link if it can be written to directly; else through the conductor
    }
    struct Link: Codable, Equatable, Sendable { var from: String; var to: String; var label: String }
    struct Message: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var agent: String           // which agent the conversation is with
        var from: String            // "you" or the agent's id
        var at: Date
        var text: String
        var replyTo: String?
    }

    var v: Int
    var made: Date
    var conductor: String           // the id of the agent that wrote this
    var agents: [Agent]
    var links: [Link]
    var messages: [Message]

    var counts: (working: Int, waiting: Int, idle: Int) {
        (agents.filter { $0.status == "working" }.count,
         agents.filter { $0.status == "waiting" || $0.status == "blocked" }.count,
         agents.filter { $0.status == "idle" || $0.status == "done" }.count)
    }

    static func decode(_ data: Data) throws -> AgentsReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentsReport.self, from: data)
    }
}

/// A message you sent to an agent, kept on this device so the conversation shows it at once.
struct SentToAgent: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var agent: String
    var at: Date
    var text: String
}
