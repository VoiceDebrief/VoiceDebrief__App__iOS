import Foundation

/// The bytes a vault path holds, and the HTTP status that came with them.
public struct VaultResponse: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) {
        self.data = data
        self.status = status
    }
}

/// How the reader reaches `bare/…` files. The server and a local folder behave the same.
public protocol VaultTransport: Sendable {
    /// GET one file. Returns status 404 (not a thrown error) when the file does not exist.
    func get(vaultId: String, path: String) async throws -> VaultResponse
    /// A label for the debug panel, e.g. "dev.send.sgraph.ai" or "folder".
    var label: String { get }
}

/// `GET <server>/api/vault/read/<vault id>/<url-encoded path>`, no auth header.
public struct HTTPVaultTransport: VaultTransport {
    /// The largest file the reader downloads (16 MB). sgit sends larger blobs through presigned uploads,
    /// which this reader does not support; anything bigger is refused, never buffered.
    public static let maxResponseBytes = 16 * 1024 * 1024
    public let server: URL
    public let session: URLSession
    public var label: String { server.host() ?? server.absoluteString }

    public init(server: URL = VaultAddress.defaultServer, session: URLSession = .shared) {
        self.server = server
        self.session = session
    }

    /// Percent-encode everything except RFC 3986 unreserved characters (as Python's quote(path, safe="")).
    public static func encode(_ path: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    public func url(vaultId: String, path: String) -> URL {
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/api/vault/read/\(Self.encode(vaultId))/\(Self.encode(path))")!
    }

    public func get(vaultId: String, path: String) async throws -> VaultResponse {
        var request = URLRequest(url: url(vaultId: vaultId, path: path))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData     // refs must never come from a cache
        request.timeoutInterval = 30
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if response.expectedContentLength > Int64(Self.maxResponseBytes) {
            bytes.task.cancel()
            throw VaultError.tooLarge(path: path, bytes: Int(response.expectedContentLength))
        }
        // Read in chunks and stop at the cap, whatever the server claims.
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        var chunk = [UInt8]()
        chunk.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == 64 * 1024 {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                if data.count > Self.maxResponseBytes {
                    bytes.task.cancel()
                    throw VaultError.tooLarge(path: path, bytes: data.count)
                }
            }
        }
        data.append(contentsOf: chunk)
        guard data.count <= Self.maxResponseBytes else { throw VaultError.tooLarge(path: path, bytes: data.count) }
        return VaultResponse(data: data, status: status)
    }
}

/// Reads `<root>/<path>`: a folder laid out as the server holds a vault (`bare/…`),
/// or a clone's `.sg_vault` folder. Used by the tests and for local clones.
public struct FolderVaultTransport: VaultTransport {
    public let root: URL
    /// When set, each vault lives in `<root>/<vault id>/<perVaultSubfolder>/`.
    public let perVaultSubfolder: String?
    public var label: String { "folder" }

    public init(root: URL, perVaultSubfolder: String? = nil) {
        self.root = root
        self.perVaultSubfolder = perVaultSubfolder
    }

    public func get(vaultId: String, path: String) async throws -> VaultResponse {
        var base = root
        if let sub = perVaultSubfolder {
            base = root.appending(path: vaultId, directoryHint: .isDirectory)
            if !sub.isEmpty { base = base.appending(path: sub, directoryHint: .isDirectory) }
        }
        let url = base.appending(path: path)
        guard let data = try? Data(contentsOf: url) else { return VaultResponse(data: Data(), status: 404) }
        return VaultResponse(data: data, status: 200)
    }
}
