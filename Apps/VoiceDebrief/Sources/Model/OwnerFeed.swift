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
        // Fields d.holacracy's team index carries (23 November 2026): kept and shown where useful.
        var circle: String?
        var lead: String?
        var model: String?
        /// The agent's home repository ("SovereignWebsite/Site__Agent__Hub") and its address.
        var home: String?
        var homeUrl: String?
        /// The repository it works in, where it has no home; may say "not recorded" or carry "(assumed)".
        var repo: String?
        var session: String?
        /// Read from another agent's report, not seen directly.
        var relayed: Bool?
        /// Proposed in the governance record, not yet confirmed.
        var proposed: Bool?
    }

    /// An agent another account reports, which the feed's writer has not seen itself.
    struct Reported: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var account: String?
        var kind: String?
        var session: String?
        var source: String?
        var as_of: String?
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
        /// Where the answer goes, sealed: an sgi1. lane link. Anything else (an agent's name): through the conductor.
        var lane: String?
        /// The slides made for it (an item id).
        var slides: String?
        /// Links to what the decision rests on: the brief, the signatures.
        var evidence: [String]?
        /// The asker's recommendation: an option's letter, or several ("AB") when options combine.
        var recommended: String?

        /// The options the recommendation names: those whose label starts with one of its letters ("B. …").
        var recommendedOptions: [String] {
            guard let recommended, !recommended.isEmpty else { return [] }
            let letters = Set(recommended.uppercased().filter(\.isLetter))
            return options.filter { option in
                guard let first = option.first, option.dropFirst().first == "." else { return option == recommended }
                return letters.contains(Character(first.uppercased()))
            }
        }
    }

    var kind: String
    var made: Date
    var by: String
    var twin: Bool?
    var about: String?
    var extra_fields: [String]?
    var agents: [Agent]
    var reported_not_seen: [Reported]?
    var sites: [Item]?
    var videos: [Item]?
    var briefs: [Item]?
    var slides: [Item]?
    var decisions: [Decision]?
    /// What was wrong with the feed and what the app did about it: a row it could not read, a repeated id, a
    /// decision without a real choice. Shown under the feed. Not part of the format.
    var problems: [String] = []

    enum CodingKeys: String, CodingKey {
        case kind, made, by, twin, about, extra_fields, agents, reported_not_seen, sites, videos, briefs, slides, decisions
    }

    enum FeedError: LocalizedError, Equatable {
        case wrongKind(String)

        var errorDescription: String? {
            switch self {
            case .wrongKind(let k): "Not an owner feed (its kind is \(k))."
            }
        }
    }

    /// A row that could not be read is left out, not the whole feed (the project's position: never lose what
    /// can be kept). Each one left out is counted in `problems`.
    private struct Lossy<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        made = try c.decode(Date.self, forKey: .made)
        by = try c.decode(String.self, forKey: .by)
        twin = try c.decodeIfPresent(Bool.self, forKey: .twin)
        about = try c.decodeIfPresent(String.self, forKey: .about)
        extra_fields = try? c.decodeIfPresent([String].self, forKey: .extra_fields)
        var dropped: [String] = []
        func rows<T: Decodable>(_ key: CodingKeys) -> [T]? {
            guard let raw = try? c.decodeIfPresent([Lossy<T>].self, forKey: key) else { return nil }
            let kept = raw.compactMap(\.value)
            if kept.count < raw.count { dropped.append("\(raw.count - kept.count) of \(raw.count) in \(key.rawValue) could not be read") }
            return kept
        }
        agents = rows(.agents) ?? []
        reported_not_seen = rows(.reported_not_seen)
        sites = rows(.sites)
        videos = rows(.videos)
        briefs = rows(.briefs)
        slides = rows(.slides)
        decisions = rows(.decisions)
        problems = dropped
    }

    init(kind: String, made: Date, by: String, twin: Bool? = nil, about: String? = nil, agents: [Agent],
         sites: [Item]? = nil, videos: [Item]? = nil, briefs: [Item]? = nil, slides: [Item]? = nil, decisions: [Decision]? = nil) {
        self.kind = kind; self.made = made; self.by = by; self.twin = twin; self.about = about; self.agents = agents
        self.sites = sites; self.videos = videos; self.briefs = briefs; self.slides = slides; self.decisions = decisions
    }

    /// Dates as feeds write them: with or without seconds, with or without fractions, or a day alone.
    static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let d = full.date(from: text) { return d }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: text) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }

    /// Reads a feed. Only a feed of another kind is refused; everything else is kept as far as it can be, and
    /// what was wrong is listed in `problems`.
    static func decode(_ data: Data) throws -> OwnerFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            guard let date = OwnerFeed.date(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Not a date: \(text)"))
            }
            return date
        }
        var feed = try decoder.decode(OwnerFeed.self, from: data)
        try feed.check()
        feed.tidy()
        return feed
    }

    func check() throws {
        guard kind == Self.kind else { throw FeedError.wrongKind(kind) }
    }

    /// Keeps the first of rows that share an id, and leaves out a decision with fewer than two choices; each is
    /// said in `problems`. An item or decision from an agent the feed does not list is kept and said too.
    mutating func tidy() {
        var seen = Set<String>()
        var notes: [String] = []
        func firsts<T: Identifiable>(_ rows: [T]?, _ what: String) -> [T]? where T.ID == String {
            guard let rows else { return nil }
            var kept: [T] = []
            for row in rows {
                if seen.insert(row.id).inserted { kept.append(row) } else { notes.append("\(what) \(row.id) is listed twice; the first is kept") }
            }
            return kept
        }
        let agentsKept = firsts(agents, "Agent") ?? []
        let sitesKept = firsts(sites, "Site"), videosKept = firsts(videos, "Video")
        let briefsKept = firsts(briefs, "Brief"), slidesKept = firsts(slides, "Slides")
        var decisionsKept = firsts(decisions, "Decision")
        decisionsKept = decisionsKept?.filter { decision in
            if decision.options.count >= 2 { return true }
            notes.append("Decision \(decision.id) has fewer than two choices and is left out")
            return false
        }
        agents = agentsKept; sites = sitesKept; videos = videosKept; briefs = briefsKept; slides = slidesKept; decisions = decisionsKept
        let known = Set(agents.map(\.id))
        for item in allItems where !known.contains(item.agent) { notes.append("\(item.title) is from \(item.agent), not in the list of agents") }
        for decision in decisions ?? [] where !known.contains(decision.from) {
            notes.append("Decision \(decision.id) is from \(decision.from), not in the list of agents")
        }
        problems += notes
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
