import Foundation
import Observation

/// The agents screen's state: which vault the conductor writes into, the latest report from it, and
/// what you have sent. Reading needs nothing but the vault; writing to an agent goes over a lane,
/// encrypted to that agent's key (today the conductor's: Claude (developer)).
@MainActor
@Observable
final class AgentsDesk {
    static let shared = AgentsDesk()
    static let vaultKey = "vd.agentsVault"

    private(set) var report: AgentsReport?
    private(set) var picture: Data?
    private(set) var problem: String?
    private(set) var loadedAt: Date?
    private(set) var sent: [SentToAgent] = []
    private(set) var sending = false
    private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "agents-sent.json")

    init() {
        if let data = try? Data(contentsOf: file) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            sent = (try? d.decode([SentToAgent].self, from: data)) ?? []
        }
    }

    var vaultId: String {
        get { UserDefaults.standard.string(forKey: Self.vaultKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.vaultKey) }
    }

    /// Pulls the vault and reads the report and its picture.
    func refresh(book: VaultBook) async {
        guard let vault = book.vaults.first(where: { $0.id == vaultId }) else { return }
        if book.current(vault).remoteId != nil { await book.pull(vault) }
        do {
            report = try AgentsReport.decode(try await book.data(of: "agents/agents.json", in: book.current(vault)))
            picture = try? await book.data(of: "agents/overview.png", in: book.current(vault))
            problem = nil
        } catch {
            problem = report == nil ? "Nothing from the conductor in this vault yet." : "Could not refresh: \(VaultBook.describe(error))"
        }
        loadedAt = Date()
    }

    /// Hands the vault to the conductor, so that it can write the report into it: its key, sealed on this
    /// device to the conductor's public key and dropped in its inbox. Nobody else can open it.
    func shareVault(_ vault: SavedVault) async throws {
        guard let lane = DeveloperLane.builtIn else { throw AgentsDeskError.noConductor }
        try await post(kind: "voicedebrief/vault-key/v1", name: "vault-key.txt", body: Data("\(vault.name)\n\(vault.keyText)".utf8), lane: lane)
        UsageLog.shared.action("agents.share-vault")
    }

    /// A message to an agent. One the conductor cannot reach directly goes through the conductor, which
    /// passes it on.
    func send(_ text: String, to agent: AgentsReport.Agent) async {
        let laneLink = agent.lane ?? DeveloperLane.builtInLink
        guard let lane = DeveloperLane.parse(laneLink) else { problem = "No way to reach \(agent.name)."; return }
        sending = true
        defer { sending = false }
        let message = SentToAgent(id: String(UUID().uuidString.lowercased().prefix(8)), agent: agent.id, at: Date(), text: text)
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try await post(kind: "voicedebrief/agent-message/v1", name: "message.json", body: try encoder.encode(message), lane: lane)
            sent.append(message)
            write()
            UsageLog.shared.action("agents.send")
        } catch {
            problem = "Not sent: \(error.localizedDescription)"
        }
    }

    /// The conversation with one agent: what you sent and what came back, in time order.
    func conversation(with agent: String) -> [AgentsReport.Message] {
        let mine = sent.filter { $0.agent == agent }.map { AgentsReport.Message(id: $0.id, agent: agent, from: "you", at: $0.at, text: $0.text, replyTo: nil) }
        let theirs = (report?.messages ?? []).filter { $0.agent == agent }
        var seen = Set<String>()
        return (theirs + mine).filter { seen.insert($0.id).inserted }.sorted { $0.at < $1.at }
    }

    private func post(kind: String, name: String, body: Data, lane: DeveloperLane) async throws {
        let header = DeveloperLane.Header(kind: kind, note: "agents-\(Int(Date().timeIntervalSince1970))", part: 1, of: 1,
                                          name: name, size: body.count, sha256: DeveloperLane.sha256Hex(body),
                                          app: AppInfo.versionLine(), sentAt: ISO8601DateFormatter().string(from: Date()))
        try await lane.send([try DeveloperLane.message(header: header, body: body)]) { _, _ in }
    }

    private func write() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(sent).write(to: file, options: .atomic)
    }
}

enum AgentsDeskError: LocalizedError {
    case noConductor
    var errorDescription: String? { "This build has no conductor to share with." }
}
