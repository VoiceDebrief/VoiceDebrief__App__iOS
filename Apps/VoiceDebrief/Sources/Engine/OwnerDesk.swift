import Foundation
import Observation

/// Owner mode's state (R6): which feed is shown, the owner's decisions and, kept apart, his actions.
///
/// Two sources. **Demo** is the synthetic twin bundled with the app (`owner-feed-twin.json`): it opens with
/// nothing set up, and nothing answered in it leaves the device. **Live** is `owner/feed.json` in the vault
/// the conductor already writes the agents report into: encrypted, readable only on the owner's devices.
/// An answer or a message is one small JSON body (`OwnerOutgoing`) sealed to the asking agent's lane, or to
/// the conductor's when the agent has none.
@MainActor
@Observable
final class OwnerDesk {
    static let shared = OwnerDesk()
    static let livePath = "owner/feed.json"

    enum Source: String, CaseIterable, Identifiable, Sendable {
        case demo, published, live
        var id: String { rawValue }
        var title: String {
            switch self {
            case .demo: "Demo"
            case .published: "Published"
            case .live: "Your vault"
            }
        }
    }

    var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "vd.owner.source") ?? "") ?? .demo {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "vd.owner.source"); feed = nil; problem = nil }
    }

    private(set) var feed: OwnerFeed?
    private(set) var problem: String?
    private(set) var loadedAt: Date?
    private(set) var sending = false
    private(set) var decisions: [OwnerDecisionRecord] = []
    private(set) var actions: [OwnerAction] = []

    private let folder: URL

    // MARK: The handshake (slice 2)

    /// The owner's grant for this install's device key, checked against the pinned owner keys. Without one, owner
    /// mode shows only its demo: no live feed, nothing sent.
    private(set) var grant: OwnerHandshake.Accepted?
    /// Why the stored grant, or one just pasted, was not accepted.
    private(set) var grantProblem: String?
    /// The last registration request made on this device, to show again.
    private(set) var request: String?

    var registered: Bool { grant != nil }
    private var grantFile: URL { folder.appending(path: "grant.txt") }

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "owner")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        decisions = Self.read([OwnerDecisionRecord].self, from: folder.appending(path: "decisions.json")) ?? []
        actions = Self.read([OwnerAction].self, from: folder.appending(path: "actions.json")) ?? []
    }

    /// Checks the stored grant against this install's device key (it is invalid after a reinstall, which wipes
    /// the key) and the owner keys this build pins.
    func checkGrant(deviceFingerprint: String?) {
        guard let text = try? String(contentsOf: grantFile, encoding: .utf8) else { grant = nil; return }
        guard let deviceFingerprint else { grant = nil; grantProblem = "This device has no key yet."; return }
        do {
            grant = try OwnerHandshake.verify(text, deviceFingerprint: deviceFingerprint)
            grantProblem = nil
        } catch {
            grant = nil
            grantProblem = error.localizedDescription
        }
    }

    /// Makes this device's registration request: its key, signed by itself, for the owner to grant.
    func makeRequest(signer: IdentityDeviceSigner, label: String) {
        do {
            request = try OwnerHandshake.request(deviceKeyPEM: signer.publicKeyPEM, fingerprint: signer.fingerprint, kept: signer.kept,
                                                 label: label, at: Date(), nonce: Self.newId(), sign: signer.sign)
            grantProblem = nil
            UsageLog.shared.action("owner.request")
        } catch {
            grantProblem = "The request was not made: \(error.localizedDescription)"
        }
    }

    func makeRequest(failed error: Error) {
        grantProblem = "This device's key is not available: \(error.localizedDescription)"
    }

    /// Takes a pasted or scanned grant; kept only if it checks out for this device.
    @discardableResult
    func accept(grant text: String, deviceFingerprint: String) -> Bool {
        do {
            grant = try OwnerHandshake.verify(text, deviceFingerprint: deviceFingerprint)
            try Data(text.utf8).write(to: grantFile, options: .atomic)
            grantProblem = nil
            UsageLog.shared.action("owner.granted")
            return true
        } catch {
            grantProblem = error.localizedDescription
            return false
        }
    }

    func forgetGrant() {
        try? FileManager.default.removeItem(at: grantFile)
        grant = nil
    }

    var isDemo: Bool { source == .demo }

    /// Public feeds in the owner.feed/v1 shape, read as they are: account D's team index, by d.holacracy (23 November
    /// 2026). Public, and committed by the agents that write them; the app only reads them.
    static let publishedFeeds = [
        "https://raw.githubusercontent.com/PrompTugal/PrompTugal__News__Website/dev/board/team/holacracy.d/team-index.json",
    ]

    /// Reads each published feed and puts them together; one that cannot be read is said, not fatal.
    static func readPublished(_ addresses: [String] = publishedFeeds,
                              get: @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) async -> OwnerFeed? {
        var feeds: [OwnerFeed] = []
        var notes: [String] = []
        for address in addresses {
            guard let url = URL(string: address) else { continue }
            do { feeds.append(try OwnerFeed.decode(try await get(url))) } catch {
                notes.append("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
            }
        }
        guard var merged = feeds.first else { return nil }
        for other in feeds.dropFirst() {
            merged.agents += other.agents
            merged.reported_not_seen = (merged.reported_not_seen ?? []) + (other.reported_not_seen ?? [])
            merged.decisions = (merged.decisions ?? []) + (other.decisions ?? [])
            merged.sites = (merged.sites ?? []) + (other.sites ?? [])
            merged.videos = (merged.videos ?? []) + (other.videos ?? [])
            merged.briefs = (merged.briefs ?? []) + (other.briefs ?? [])
            merged.slides = (merged.slides ?? []) + (other.slides ?? [])
            merged.problems += other.problems
            merged.by += ", " + other.by
        }
        merged.problems += notes
        return merged
    }

    /// Reads the feed again from its source.
    func refresh(book: VaultBook) async {
        switch source {
        case .demo:
            feed = OwnerFeed.bundledTwin()
            problem = feed == nil ? "The demo feed is missing from this build." : nil
        case .published:
            feed = await Self.readPublished()
            problem = feed == nil ? "No published feed could be read just now." : nil
        case .live:
            guard registered else {
                feed = nil
                problem = "Live opens on a device the owner has registered (This device, above). Demo works anywhere."
                break
            }
            let vaultId = AgentsDesk.shared.vaultId
            guard let vault = book.vaults.first(where: { $0.id == vaultId }) else {
                feed = nil
                problem = "Choose the agents vault on the Agents screen first: the live feed is read from \(Self.livePath) in it."
                break
            }
            if book.current(vault).remoteId != nil { await book.pull(vault) }
            do {
                feed = try OwnerFeed.decode(try await book.data(of: Self.livePath, in: book.current(vault)))
                problem = nil
            } catch let error as OwnerFeed.FeedError {
                problem = error.localizedDescription
            } catch {
                problem = feed == nil ? "No owner feed in this vault yet (\(Self.livePath))." : "Could not refresh: \(VaultBook.describe(error))"
            }
        }
        loadedAt = Date()
    }

    func decided(_ decision: OwnerFeed.Decision) -> OwnerDecisionRecord? {
        decisions.last { $0.id == decision.id }
    }

    /// Answers a decision. In demo mode it is recorded and not sent.
    func answer(_ decision: OwnerFeed.Decision, with choice: String) async {
        let outgoing = OwnerOutgoing.answer(decision, choice: choice, app: AppInfo.versionLine(), at: Date(), id: Self.newId())
        guard let delivery = await deliver(outgoing, lane: decision.lane, name: "answer.json") else { return }
        decisions.append(OwnerDecisionRecord(id: decision.id, title: decision.title, choice: choice, from: decision.from, at: outgoing.at, delivery: delivery))
        Self.write(decisions, to: folder.appending(path: "decisions.json"))
        UsageLog.shared.action("owner.decision")
    }

    /// Talks to a page: a message about one item, to the agent that made it. An action, not a decision.
    func talk(about item: OwnerFeed.Item?, to agentId: String, text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let outgoing = OwnerOutgoing.message(about: item, to: agentId, text: text, app: AppInfo.versionLine(), at: Date(), id: Self.newId())
        let lane = feed?.agent(agentId)?.lane
        guard let delivery = await deliver(outgoing, lane: lane, name: "message.json") else { return }
        actions.append(OwnerAction(id: outgoing.id, kind: item == nil ? "message" : "talk-to-page",
                                   subject: item?.title ?? (feed?.agent(agentId)?.name ?? agentId), text: text, at: outgoing.at, delivery: delivery))
        Self.write(actions, to: folder.appending(path: "actions.json"))
        UsageLog.shared.action("owner.talk")
    }

    /// Seals and sends one body; returns how it went, or nil (with `problem` set) when it was not sent.
    private func deliver(_ outgoing: OwnerOutgoing, lane laneLink: String?, name: String) async -> String? {
        if isDemo || feed?.twin == true { return "Not sent: demo" }
        guard registered else { problem = "Not sent: this device is not registered by the owner."; return nil }
        guard let lane = DeveloperLane.parse(laneLink ?? "") ?? DeveloperLane.builtIn else {
            problem = "No lane to send on."; return nil
        }
        sending = true
        defer { sending = false }
        do {
            let body = try outgoing.encoded()
            let header = DeveloperLane.Header(kind: outgoing.kind, note: "owner-\(outgoing.id)", part: 1, of: 1,
                                              name: name, size: body.count, sha256: DeveloperLane.sha256Hex(body),
                                              app: outgoing.app, sentAt: ISO8601DateFormatter().string(from: outgoing.at))
            try await lane.send([try DeveloperLane.message(header: header, body: body)]) { _, _ in }
            problem = nil
            let via = laneLink == nil ? "the conductor" : outgoing.to
            return "Sealed to \(via) (\(lane.fingerprint))"
        } catch {
            problem = "Not sent: \(error.localizedDescription)"
            return nil
        }
    }

    private static func newId() -> String { String(UUID().uuidString.lowercased().prefix(8)) }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(value).write(to: url, options: .atomic)
    }
}
