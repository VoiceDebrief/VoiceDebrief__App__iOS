import CryptoKit
import Foundation

/// The keys to one's own inbox: its address, the enumeration key that lists and fetches what arrived, and
/// the key of the vault it lives on. Secret: kept in the secrets store, never in a card.
public struct InboxKeys: Codable, Equatable, Sendable {
    public var address: InboxAddress
    /// Lists, fetches and marks processed (`x-sgraph-vault-enum-key`). The server holds only its hash.
    public var enumKey: String
    /// The vault's key, `sgit_private_vault_…:<vault id>`: it configures the lane.
    public var vaultKey: String

    public init(address: InboxAddress, enumKey: String, vaultKey: String) {
        self.address = address
        self.enumKey = enumKey
        self.vaultKey = vaultKey
    }
}

/// One POST and its answer. The app uses URLSession; tests replay answers recorded from the live server.
public protocol LaneHTTP: Sendable {
    func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (status: Int, body: Data)
}

public struct URLSessionLaneHTTP: LaneHTTP {
    public let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

/// One message waiting in a lane, as `list` answers (dev.send.sgraph.ai, 14 November 2026):
/// `{"inbox": <lane>, "file_id": "1794649267280_0c45….enc", "received": 1794649267280}`, with `size` and
/// `content` when the list was asked for content.
public struct LaneEntry: Codable, Equatable, Sendable {
    public var inbox: String
    public var fileId: String
    /// Milliseconds since 1970.
    public var received: Int64
    public var size: Int?
    public var content: String?

    enum CodingKeys: String, CodingKey {
        case inbox, received, size, content
        case fileId = "file_id"
    }

    public var receivedAt: Date { Date(timeIntervalSince1970: Double(received) / 1000) }
}

public struct LaneFile: Codable, Equatable, Sendable {
    public var fileId: String
    public var size: Int?
    public var content: String

    enum CodingKeys: String, CodingKey {
        case size, content
        case fileId = "file_id"
    }
}

public enum LaneError: Error, Equatable, LocalizedError {
    /// The server answers 404 when the vault or lane does not exist, and equally when an append token or
    /// enumeration key does not match: it does not say which.
    case notFound
    case tooLarge
    case refused(Int)
    case badAnswer(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: "The inbox was not found: it does not exist, or the key or token does not match."
        case .tooLarge: "The message is too large for the inbox."
        case .refused(let status): "The server refused (status \(status))."
        case .badAnswer(let why): "The server's answer did not read (\(why))."
        }
    }
}

/// The append-lane routes of an sgit vault server (`/api/vault/append/<operation>/<vault id>`), as
/// dev.send.sgraph.ai answered them on 14 November 2026:
///
///   write            `{append_token, payload}`; no other credential; `{"ok": true}`
///   list             enum key header; `{include_content}`; `{"status": "ok", "entries": [...], "truncated": false}`
///   fetch            enum key header; `{inbox, file_ids}`; `{"status": "ok", "files": [...], "missing": []}`
///   mark-processed   enum key header; `{inbox, file_ids}`; `{"status": "ok", "moved": [...], "missing": []}`
///   configure        write key and access token headers; `{append_anchors, enum_key_hash}`;
///                    `{"vault_id": …, "status": "configured"}`
///
/// A wrong token or key, and a lane that does not exist, all answer 404 with an HTML page.
public struct LaneClient: Sendable {
    public let http: any LaneHTTP

    public init(http: any LaneHTTP = URLSessionLaneHTTP()) { self.http = http }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `count` random bytes as hex: append tokens are 24 bytes, enumeration keys 32, as the conductor makes them.
    public static func randomHex(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func call(_ address: InboxAddress, _ operation: String, _ body: [String: Any],
                      headers: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = address.url(operation) else { throw LaneError.badAnswer("no address") }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (status, answer) = try await http.post(url, body: data, headers: headers)
        switch status {
        case 200..<300: break
        case 404: throw LaneError.notFound
        case 413: throw LaneError.tooLarge
        default: throw LaneError.refused(status)
        }
        guard let json = try? JSONSerialization.jsonObject(with: answer) as? [String: Any] else { throw LaneError.badAnswer("not a JSON object") }
        return json
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value),
              let out = try? JSONDecoder().decode(type, from: data) else { throw LaneError.badAnswer("\(T.self)") }
        return out
    }

    /// Drops one payload in someone's inbox.
    public func write(_ payload: String, to address: InboxAddress) async throws {
        let answer = try await call(address, "write", ["append_token": address.append, "payload": payload])
        guard answer["ok"] as? Bool == true else { throw LaneError.badAnswer("write was not ok") }
    }

    private func enumHeader(_ keys: InboxKeys) -> [String: String] { ["x-sgraph-vault-enum-key": keys.enumKey] }

    public func list(_ keys: InboxKeys, includeContent: Bool = false) async throws -> (entries: [LaneEntry], truncated: Bool) {
        let answer = try await call(keys.address, "list", ["include_content": includeContent], headers: enumHeader(keys))
        return (try decode([LaneEntry].self, answer["entries"] ?? []), answer["truncated"] as? Bool ?? false)
    }

    public func fetch(_ keys: InboxKeys, inbox: String, fileIds: [String]) async throws -> (files: [LaneFile], missing: [String]) {
        let answer = try await call(keys.address, "fetch", ["inbox": inbox, "file_ids": fileIds], headers: enumHeader(keys))
        return (try decode([LaneFile].self, answer["files"] ?? []), answer["missing"] as? [String] ?? [])
    }

    public func markProcessed(_ keys: InboxKeys, inbox: String, fileIds: [String]) async throws -> (moved: [String], missing: [String]) {
        let answer = try await call(keys.address, "mark-processed", ["inbox": inbox, "file_ids": fileIds], headers: enumHeader(keys))
        return (answer["moved"] as? [String] ?? [], answer["missing"] as? [String] ?? [])
    }

    /// Opens a lane on a vault: the server keeps the hash of each append token it will accept and the hash of
    /// the enumeration key. Needs the vault's write key and the server's access key.
    public func configure(_ address: InboxAddress, writeKeyHex: String, accessToken: String, enumKey: String) async throws {
        let answer = try await call(address, "configure",
                                    ["append_anchors": [Self.sha256Hex(address.append)], "enum_key_hash": Self.sha256Hex(enumKey)],
                                    headers: ["x-sgraph-vault-write-key": writeKeyHex, "x-sgraph-access-token": accessToken])
        guard answer["status"] as? String == "configured" else { throw LaneError.badAnswer("not configured") }
    }
}
