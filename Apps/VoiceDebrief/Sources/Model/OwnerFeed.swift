import Foundation

/// The owner feed, `owner.feed/v1`: everything the owner mode shows, in one committed JSON file (R6 of the
/// 23 November 2026 brief: "read everything from committed JSON and the agents' published state, not from
/// HTML"). The contract is written down at `website/owner/index.md` so that whoever indexes the agents can
/// publish to it. The app draws it and never makes any of it up.
struct OwnerFeed: Codable, Equatable, Sendable {
    static let kind = "owner.feed/v1"

    struct Agent: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var account: String?
        /// "maestro", "agent", "subagent", "signer": from the biggest to the smallest.
        var kind: String
        var parent: String?
        /// "working", "waiting", "idle", "blocked", "done".
        var status: String
        var doing: String
        var waitingFor: String?
        var site: String?
        /// Where the agent publishes its own state as JSON (a status.json).
        var statusURL: String?
        /// An sgi1. lane link if it can be written to directly; otherwise messages go through the conductor.
        var lane: String?
        var updated: Date?
    }

    /// One thing an agent made: a site, a video, a brief or a set of slides.
    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var url: String
        var agent: String
        var made: Date
        var summary: String?
        var seconds: Int?
        var signedBy: [String]?
        /// For slides: the decision they are for.
        var decision: String?
    }

    struct Decision: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var detail: String?
        var options: [String]
        var from: String
        var at: Date
        /// Where the answer goes, sealed: the asking agent's own lane. None: through the conductor.
        var lane: String?
        /// The slides made for it (an item id).
        var slides: String?
        /// Links to what the decision rests on: the brief, the signatures.
        var evidence: [String]?
    }

    var kind: String
    var made: Date
    var by: String
    var twin: Bool?
    var about: String?
    var agents: [Agent]
    var sites: [Item]?
    var videos: [Item]?
    var briefs: [Item]?
    var slides: [Item]?
    var decisions: [Decision]?

    enum FeedError: LocalizedError, Equatable {
        case wrongKind(String)
        case repeatedId(String)
        case unknownAgent(String)
        case noOptions(String)

        var errorDescription: String? {
            switch self {
            case .wrongKind(let k): "Not an owner feed (its kind is \(k))."
            case .repeatedId(let id): "The id \(id) is used twice."
            case .unknownAgent(let id): "\(id) names an agent the feed does not list."
            case .noOptions(let id): "Decision \(id) has fewer than two choices."
            }
        }
    }

    /// Reads a feed and checks what the app relies on: the kind, unique ids, every item and decision from
    /// a listed agent, and every decision with a real choice.
    static func decode(_ data: Data) throws -> OwnerFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feed = try decoder.decode(OwnerFeed.self, from: data)
        try feed.check()
        return feed
    }

    func check() throws {
        guard kind == Self.kind else { throw FeedError.wrongKind(kind) }
        let agentIds = agents.map(\.id)
        var seen = Set<String>()
        for id in agentIds + allItems.map(\.id) + (decisions ?? []).map(\.id) where !seen.insert(id).inserted {
            throw FeedError.repeatedId(id)
        }
        let known = Set(agentIds)
        for item in allItems where !known.contains(item.agent) { throw FeedError.unknownAgent(item.agent) }
        for decision in decisions ?? [] {
            if !known.contains(decision.from) { throw FeedError.unknownAgent(decision.from) }
            if decision.options.count < 2 { throw FeedError.noOptions(decision.id) }
        }
    }

    var allItems: [Item] { (sites ?? []) + (videos ?? []) + (briefs ?? []) + (slides ?? []) }

    func agent(_ id: String) -> Agent? { agents.first { $0.id == id } }

    /// Agents from the biggest to the smallest, then by name.
    var agentsBySize: [Agent] {
        let order = ["maestro", "agent", "signer", "subagent"]
        return agents.sorted {
            let a = order.firstIndex(of: $0.kind) ?? order.count, b = order.firstIndex(of: $1.kind) ?? order.count
            return a != b ? a < b : $0.name < $1.name
        }
    }

    static let twinResource = "owner-feed-twin"

    static func bundledTwin(_ bundle: Bundle = .main) -> OwnerFeed? {
        guard let url = bundle.url(forResource: twinResource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}

/// A decision the owner made on this device. Kept apart from his actions (the brief: "keep Dinis's decisions
/// apart from his actions"): a decision answers a question an agent asked; an action is something he did.
struct OwnerDecisionRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String              // the decision's id
    var title: String
    var choice: String
    var from: String            // the agent that asked
    var at: Date
    /// "sealed to <lane fingerprint>", or "not sent: demo" for the twin.
    var delivery: String
}

/// Something the owner did in owner mode that is not a decision: a message to a page's agent, a feed chosen.
struct OwnerAction: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: String            // "talk-to-page", "message", "feed"
    var subject: String
    var text: String?
    var at: Date
    var delivery: String
}

/// What is sealed and sent for one answer or one message: a small JSON body, `owner.answer/v1` or
/// `owner.message/v1`, so the receiving agent reads it without parsing prose.
struct OwnerOutgoing: Codable, Equatable, Sendable {
    static let answerKind = "owner.answer/v1"
    static let messageKind = "owner.message/v1"

    var kind: String
    var id: String
    var at: Date
    var to: String              // the agent's id
    var decision: String?
    var choice: String?
    /// For a message about a page: the page's address and title, so the agent knows what it is about.
    var page: String?
    var pageTitle: String?
    var text: String?
    var app: String

    static func answer(_ decision: OwnerFeed.Decision, choice: String, app: String, at: Date, id: String) -> OwnerOutgoing {
        OwnerOutgoing(kind: answerKind, id: id, at: at, to: decision.from, decision: decision.id, choice: choice, app: app)
    }

    static func message(about item: OwnerFeed.Item?, to agent: String, text: String, app: String, at: Date, id: String) -> OwnerOutgoing {
        OwnerOutgoing(kind: messageKind, id: id, at: at, to: agent, page: item?.url, pageTitle: item?.title, text: text, app: app)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
