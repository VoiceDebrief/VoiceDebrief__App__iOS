import CryptoKit
import Foundation
import Observation

/// Sites (R7, tier 1): the Sovereign Websites this device can talk to. A site is added by scanning its QR code,
/// a link to its `/send/` page whose `#key=` fragment carries the person's key, issued by the site's keeper. The
/// key goes into the Keychain and is never shown again; the list keeps only the site's address and whose key it is.
///
/// Talking to a site: what is said (spoken, transcribed on the device, or typed) becomes a `ccm.request/v1`, signed
/// with the person's key, sealed to the keeper and appended to the keeper's lane, exactly as the site's own page
/// sends it. The keeper's answers are read from `send/replies/<person>.json` on the site and opened on the device.
/// While a site is open the desk looks again every 30 seconds for answers and for a change to the site's page.
@MainActor
@Observable
final class SitesDesk {
    static let shared = SitesDesk()

    struct Site: Codable, Hashable, Identifiable, Sendable {
        var origin: String          // https://chiswick-cheese-market.organisation.sovereignweb.site
        var person: String
        var fingerprint: String
        var added: Date
        var id: String { origin }
        var name: String { URL(string: origin)?.host?.components(separatedBy: ".").first?.replacingOccurrences(of: "-", with: " ").capitalized ?? origin }
    }

    struct Sent: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var site: String
        var kind: String
        var text: String
        var at: Date
    }

    private(set) var sites: [Site] = []
    private(set) var sent: [Sent] = []
    private(set) var replies: [String: [SiteReply]] = [:]
    /// Answers not yet seen on the site's screen, by site.
    private(set) var unseen: [String: Int] = [:]
    /// The site's page changed since it was last shown.
    private(set) var changed: Set<String> = []
    private(set) var problem: String?
    private(set) var sending = false
    private(set) var lastCheck: Date?

    private var pageHash: [String: String] = [:]
    private var seen: Set<String> = []
    private let folder: URL
    private let keys: any IdentityKeyStore
    private let http: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "sites"),
         keys: any IdentityKeyStore = IdentityKeychain(service: "ai.voicedebrief.app.sites"),
         http: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.folder = folder
        self.keys = keys
        self.http = http
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        sites = (try? d.decode([Site].self, from: Data(contentsOf: folder.appending(path: "sites.json")))) ?? []
        sent = (try? d.decode([Sent].self, from: Data(contentsOf: folder.appending(path: "sent.json")))) ?? []
        seen = Set((try? d.decode([String].self, from: Data(contentsOf: folder.appending(path: "seen.json")))) ?? [])
    }

    // MARK: Adding a site

    /// From the site's QR code or a pasted link: `https://<site>/send/#key=<code>`. Checks the key and that the site
    /// has a keeper's inbox before anything is kept.
    @discardableResult
    func add(link: String) async -> Site? {
        problem = nil
        do {
            let key = try SitePersonKey.from(link: link)
            guard let range = link.range(of: #"https://[A-Za-z0-9.-]+"#, options: .regularExpression) else {
                problem = "The link has no site address (https://…)."; return nil
            }
            let origin = String(link[range])
            _ = try await inbox(origin)
            let site = Site(origin: origin, person: key.person, fingerprint: key.fingerprint, added: Date())
            keys.set(Self.keyItem(origin), Data(key.packed.utf8), .synchronised)
            sites.removeAll { $0.origin == origin }
            sites.append(site)
            save()
            UsageLog.shared.action("sites.added")
            return site
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }

    func remove(_ site: Site) {
        keys.set(Self.keyItem(site.origin), nil, .synchronised)
        sites.removeAll { $0.origin == site.origin }
        save()
    }

    static func keyItem(_ origin: String) -> String { "site-key:" + origin }

    func key(for site: Site) throws -> SitePersonKey {
        guard let data = keys.get(Self.keyItem(site.origin), .synchronised), let code = String(data: data, encoding: .utf8) else {
            throw SiteSend.Failure.notAKeyLink
        }
        return try SitePersonKey.unpack(code)
    }

    private func inbox(_ origin: String) async throws -> SiteInbox {
        try SiteInbox.decode(try await get("\(origin)/send/inbox.json"))
    }

    // MARK: Talking to the keeper

    /// Sends what was said to the site's keeper. Returns true when the keeper's lane took it.
    @discardableResult
    func send(_ text: String, kind: String = "change", to site: Site) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        sending = true
        defer { sending = false }
        do {
            let inbox = try await inbox(site.origin)
            let key = try key(for: site)
            let at = Date()
            let request = try key.request(kind: kind, text: text, inbox: inbox, site: site.origin, at: at)
            try await inbox.lane().send([request]) { _, _ in }
            sent.append(Sent(id: String(UUID().uuidString.prefix(8)).lowercased(), site: site.origin, kind: kind, text: text, at: at))
            save()
            problem = nil
            UsageLog.shared.action("sites.sent")
            return true
        } catch {
            problem = "Not sent: \(error.localizedDescription)"
            return false
        }
    }

    /// Reads the keeper's answers and the site's page again.
    func check(_ site: Site) async {
        lastCheck = Date()
        do {
            let key = try key(for: site)
            let data = try await get("\(site.origin)/send/replies/\(site.person).json", missingIsEmpty: true)
            let envelopes = data.isEmpty ? [] : try JSONDecoder().decode([SitePersonKey.Envelope].self, from: data)
            var opened: [SiteReply] = []
            for envelope in envelopes {
                if let plain = try? key.open(envelope), let reply = try? JSONDecoder().decode(SiteReply.self, from: plain) { opened.append(reply) }
            }
            replies[site.origin] = opened.sorted { ($0.at ?? "") > ($1.at ?? "") }
            unseen[site.origin] = opened.filter { !seen.contains($0.id) }.count
        } catch {
            problem = "Could not read the answers: \(error.localizedDescription)"
        }
        if let page = try? await get(site.origin + "/") {
            let hash = SHA256.hash(data: page).map { String(format: "%02x", $0) }.joined()
            if let before = pageHash[site.origin], before != hash { changed.insert(site.origin) }
            pageHash[site.origin] = hash
        }
    }

    /// The answers have been shown: they are no longer new.
    func markSeen(_ site: Site) {
        for reply in replies[site.origin] ?? [] { seen.insert(reply.id) }
        unseen[site.origin] = 0
        let e = JSONEncoder()
        try? e.encode(Array(seen)).write(to: folder.appending(path: "seen.json"), options: .atomic)
    }

    /// The site's page has been shown again after a change.
    func reloaded(_ site: Site) { changed.remove(site.origin) }

    private func get(_ address: String, missingIsEmpty: Bool = false) async throws -> Data {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await http(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404, missingIsEmpty { return Data() }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return data
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(sites).write(to: folder.appending(path: "sites.json"), options: .atomic)
        try? e.encode(sent).write(to: folder.appending(path: "sent.json"), options: .atomic)
    }
}
