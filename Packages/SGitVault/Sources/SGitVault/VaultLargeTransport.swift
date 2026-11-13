import Foundation

/// Moving one large object between a file on the device and a place that holds vaults.
///
/// sgit does not put an encrypted blob over 4 MB in a batch (the server sits behind a gateway with a
/// body limit). It uploads it in parts to URLs the server signs, and reads it back from a signed URL in
/// byte ranges. Both directions here go from and to a file, so the object is never held whole in memory.
public protocol VaultLargeTransport: Sendable {
    /// Uploads the file at `file` as the object `fileId` (`bare/data/<id>`).
    /// - Parameter progress: called with the bytes sent so far.
    func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                     progress: @escaping @Sendable (Int) -> Void) async throws

    /// Downloads the object `fileId` into `file`. The caller checks the bytes against the object id.
    /// - Parameter progress: called with the bytes received so far.
    func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                       progress: @escaping @Sendable (Int) -> Void) async throws
}

/// A transport that can do everything a writer of large files needs.
public typealias VaultFileTransport = VaultTransport & VaultWriteTransport & VaultLargeTransport

/// Bytes moved by several parts at once, added up.
final class VaultByteTally: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [Int: Int] = [:]
    private let report: @Sendable (Int) -> Void

    init(report: @escaping @Sendable (Int) -> Void) { self.report = report }

    func set(part: Int, bytes: Int) {
        lock.lock()
        parts[part] = bytes
        let total = parts.values.reduce(0, +)
        lock.unlock()
        report(total)
    }
}

/// Reports the bytes one upload task has sent.
private final class VaultUploadWatcher: NSObject, URLSessionTaskDelegate, Sendable {
    let report: @Sendable (Int) -> Void
    init(report: @escaping @Sendable (Int) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        report(Int(totalBytesSent))
    }
}

struct VaultPresignedUpload: Decodable, Sendable {
    struct Part: Decodable, Sendable {
        let part_number: Int
        let upload_url: String
    }
    let upload_id: String
    let part_urls: [Part]
    let part_size: Int?
}

struct VaultPresignedRead: Decodable, Sendable {
    let url: String?
    let presigned_url: String?
    let expires_in: Int?
}

struct VaultUploadedPart: Sendable {
    let number: Int
    let etag: String
}

extension HTTPVaultTransport: VaultLargeTransport {
    /// sgit's part size for an upload (the server's maximum), and its range size for a download.
    public static let uploadPartBytes = 10 * 1024 * 1024
    public static let downloadRangeBytes = 8 * 1024 * 1024
    /// Parts or ranges in flight at once. Each holds one part in memory.
    public static let partsInFlight = 3
    /// A server without the presigned route (a self-hosted one) takes a large object in a batch, which
    /// means holding it in memory once as base64. Above this the upload is refused instead.
    public static let largestBatchFallbackBytes = 64 * 1024 * 1024

    private var base: String {
        var text = server.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, writeKey: String? = nil,
                      accessToken: String?) async throws -> (status: Int, data: Data) {
        guard let url = URL(string: "\(base)/api/vault/\(path)") else {
            throw VaultError.malformed(path: path, detail: "not a URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let writeKey { request.setValue(writeKey, forHTTPHeaderField: "x-sgraph-vault-write-key") }
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "x-sgraph-access-token")
            request.setValue(accessToken, forHTTPHeaderField: "X-API-Key")
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// True when the answer means "this server has no presigned route" (as sgit reads it): a memory or
    /// disk backend answers 400 with "S3 storage mode required", an older server 404 or 501.
    static func presignedUnavailable(status: Int, body: Data) -> Bool {
        if status == 400 || status == 404 || status == 501 { return true }
        let text = String(decoding: body.prefix(2_000), as: UTF8.self)
        return text.contains("presigned_not_available") || text.contains("S3 storage mode")
    }

    /// https to any host; http only to this machine or to the vault server's own host when that server
    /// is itself http (a self-hosted server on a local network). Nothing else: the URL comes from the server.
    func allowsSigned(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        if url.scheme == "https" { return true }
        guard url.scheme == "http" else { return false }
        if ["127.0.0.1", "localhost", "::1"].contains(host) { return true }
        return server.scheme == "http" && server.host()?.lowercased() == host
    }

    // MARK: Upload

    public func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                            progress: @escaping @Sendable (Int) -> Void) async throws {
        let size = try VaultFileCipher.byteCount(of: file)
        let wanted = max(1, (size + Self.uploadPartBytes - 1) / Self.uploadPartBytes)
        let vault = Self.encode(vaultId)
        let started = try await call("POST", "presigned/initiate/\(vault)",
                                     body: ["file_id": fileId, "file_size_bytes": size, "num_parts": wanted],
                                     writeKey: writeKey, accessToken: accessToken)
        guard (200..<300).contains(started.status) else {
            if started.status != 401, started.status != 403,
               Self.presignedUnavailable(status: started.status, body: started.data) {
                try await uploadInOneBatch(vaultId: vaultId, fileId: fileId, file: file, size: size,
                                           writeKey: writeKey, accessToken: accessToken)
                progress(size)
                return
            }
            throw VaultError.http(status: started.status, path: "presigned/initiate")
        }
        guard let upload = try? JSONDecoder().decode(VaultPresignedUpload.self, from: started.data),
              !upload.part_urls.isEmpty else {
            throw VaultError.malformed(path: "presigned/initiate", detail: "no upload id or part URLs")
        }
        let partSize = upload.part_size ?? Self.uploadPartBytes
        let tally = VaultByteTally(report: progress)
        do {
            let done = try await withThrowingTaskGroup(of: VaultUploadedPart.self,
                                                       returning: [VaultUploadedPart].self) { group in
                var waiting = upload.part_urls.sorted { $0.part_number < $1.part_number }[...]
                var finished: [VaultUploadedPart] = []
                for _ in 0..<Self.partsInFlight {
                    guard let part = waiting.popFirst() else { break }
                    group.addTask {
                        try await self.put(part: part, of: file, partSize: partSize, total: size, tally: tally)
                    }
                }
                for try await part in group {
                    finished.append(part)
                    guard let next = waiting.popFirst() else { continue }
                    group.addTask {
                        try await self.put(part: next, of: file, partSize: partSize, total: size, tally: tally)
                    }
                }
                return finished.sorted { $0.number < $1.number }
            }
            let parts: [[String: Any]] = done.map { ["part_number": $0.number, "etag": $0.etag] }
            let completed = try await call("POST", "presigned/complete/\(vault)",
                                           body: ["file_id": fileId, "upload_id": upload.upload_id, "parts": parts],
                                           writeKey: writeKey, accessToken: accessToken)
            guard (200..<300).contains(completed.status) else {
                throw VaultError.http(status: completed.status, path: "presigned/complete")
            }
        } catch {
            // Best effort: tell the server to drop the parts it holds. The object does not exist either way.
            _ = try? await call("POST", "presigned/cancel/\(vault)",
                                body: ["upload_id": upload.upload_id, "file_id": fileId],
                                writeKey: writeKey, accessToken: accessToken)
            throw error
        }
    }

    /// One part: read it from the file, PUT it to its signed URL, keep the ETag. Tried three times.
    private func put(part: VaultPresignedUpload.Part, of file: URL, partSize: Int, total: Int,
                     tally: VaultByteTally) async throws -> VaultUploadedPart {
        guard let url = URL(string: part.upload_url), allowsSigned(url) else {
            throw VaultError.malformed(path: "presigned part \(part.part_number)", detail: "refusing a part URL that is not https")
        }
        let offset = (part.part_number - 1) * partSize
        let length = min(partSize, total - offset)
        guard offset >= 0, length > 0 else {
            throw VaultError.malformed(path: "presigned part \(part.part_number)", detail: "part outside the file")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        guard let body = try handle.read(upToCount: length), body.count == length else {
            throw VaultError.malformed(path: file.lastPathComponent, detail: "the file changed while it was being sent")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 300
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let number = part.part_number
        var last: Error = VaultError.http(status: 0, path: "presigned part \(number)")
        for attempt in 1...3 {
            try Task.checkCancellation()
            do {
                let watcher = VaultUploadWatcher { sent in tally.set(part: number, bytes: sent) }
                let (_, response) = try await session.upload(for: request, from: body, delegate: watcher)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if (200..<300).contains(status), let etag = http?.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
                    tally.set(part: number, bytes: length)
                    return VaultUploadedPart(number: number, etag: etag)
                }
                last = VaultError.http(status: status, path: "presigned part \(number)")
                if status == 403 { break }          // the signed URL has expired: trying again cannot help
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = error
            }
            tally.set(part: number, bytes: 0)
            if attempt < 3 { try await Task.sleep(for: .seconds(attempt * 2)) }
        }
        throw last
    }

    private func uploadInOneBatch(vaultId: String, fileId: String, file: URL, size: Int, writeKey: String,
                                  accessToken: String?) async throws {
        guard size <= Self.largestBatchFallbackBytes else {
            throw VaultError.tooLarge(path: fileId, bytes: size)
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let result = try await batch(vaultId: vaultId, writeKey: writeKey, accessToken: accessToken,
                                     operations: [VaultBatchOperation(op: .write, fileId: fileId, data: data)])
        guard result == .ok else { throw VaultError.http(status: 409, path: fileId) }
    }

    // MARK: Download

    private struct RangeAnswer: Sendable {
        let start: Int
        let data: Data
        let total: Int?
        let partial: Bool
    }

    private func range(_ url: URL, start: Int, end: Int) async throws -> RangeAnswer {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        var last: Error = VaultError.http(status: 0, path: "presigned range")
        for attempt in 1...3 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 200 || status == 206 {
                    var total: Int?
                    if let header = http?.value(forHTTPHeaderField: "Content-Range"),
                       let slash = header.lastIndex(of: "/") {
                        total = Int(header[header.index(after: slash)...])
                    }
                    return RangeAnswer(start: start, data: data, total: total, partial: status == 206)
                }
                last = VaultError.http(status: status, path: "presigned range")
                if status == 403 || status == 404 { break }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = error
            }
            if attempt < 3 { try await Task.sleep(for: .seconds(attempt * 2)) }
        }
        throw last
    }

    public func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                              progress: @escaping @Sendable (Int) -> Void) async throws {
        let asked = try await call("GET", "presigned/read-url/\(Self.encode(vaultId))/\(Self.encode(fileId))",
                                   accessToken: accessToken)
        guard (200..<300).contains(asked.status) else {
            if asked.status != 401, asked.status != 403,
               Self.presignedUnavailable(status: asked.status, body: asked.data) {
                try await downloadWhole(vaultId: vaultId, fileId: fileId, to: file, accessToken: accessToken)
                progress((try? VaultFileCipher.byteCount(of: file)) ?? 0)
                return
            }
            throw VaultError.http(status: asked.status, path: "presigned/read-url")
        }
        let info = try? JSONDecoder().decode(VaultPresignedRead.self, from: asked.data)
        guard let text = info?.url ?? info?.presigned_url, !text.isEmpty else {
            try await downloadWhole(vaultId: vaultId, fileId: fileId, to: file, accessToken: accessToken)
            progress((try? VaultFileCipher.byteCount(of: file)) ?? 0)
            return
        }
        guard let url = URL(string: text), allowsSigned(url) else {
            throw VaultError.malformed(path: "presigned/read-url", detail: "refusing a download URL that is not https")
        }

        let step = Self.downloadRangeBytes
        let first = try await range(url, start: 0, end: step - 1)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            throw VaultError.malformed(path: file.lastPathComponent, detail: "could not create the file")
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.write(contentsOf: first.data)
        progress(first.data.count)
        // A host that ignores Range answers 200 with everything.
        guard first.partial else { return }
        guard let total = expectedBytes ?? first.total else {
            throw VaultError.malformed(path: fileId, detail: "the download gave no length")
        }
        guard total > first.data.count else { return }
        guard first.data.count == step else {
            throw VaultError.malformed(path: fileId, detail: "a range came back short")
        }

        var received = first.data.count
        try await withThrowingTaskGroup(of: RangeAnswer.self) { group in
            var starts = Array(stride(from: step, to: total, by: step))[...]
            for _ in 0..<Self.partsInFlight {
                guard let start = starts.popFirst() else { break }
                group.addTask { try await self.range(url, start: start, end: min(start + step, total) - 1) }
            }
            for try await answer in group {
                let want = min(answer.start + step, total) - answer.start
                guard answer.data.count == want else {
                    throw VaultError.malformed(path: fileId, detail: "a range came back with \(answer.data.count) bytes, not \(want)")
                }
                try handle.seek(toOffset: UInt64(answer.start))
                try handle.write(contentsOf: answer.data)
                received += answer.data.count
                progress(received)
                guard let next = starts.popFirst() else { continue }
                group.addTask { try await self.range(url, start: next, end: min(next + step, total) - 1) }
            }
        }
    }

    /// The ordinary read route, straight into a file, with no size limit. A server without the presigned
    /// route has no gateway limit either (this is what sgit does).
    private func downloadWhole(vaultId: String, fileId: String, to file: URL, accessToken: String?) async throws {
        var request = URLRequest(url: url(vaultId: vaultId, path: fileId))
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "x-sgraph-access-token")
            request.setValue(accessToken, forHTTPHeaderField: "X-API-Key")
        }
        let (temporary, response) = try await session.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            if status == 404 { throw VaultError.notFound(path: fileId) }
            throw VaultError.http(status: status, path: fileId)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
    }
}

extension FolderVaultTransport: VaultLargeTransport {
    private func place(_ vaultId: String, _ fileId: String) -> URL {
        var base = root
        if let sub = perVaultSubfolder {
            base = root.appending(path: vaultId, directoryHint: .isDirectory)
            if !sub.isEmpty { base = base.appending(path: sub, directoryHint: .isDirectory) }
        }
        return base.appending(path: fileId)
    }

    /// A folder takes a large object as a copy of the file.
    public func uploadLarge(vaultId: String, fileId: String, from file: URL, writeKey: String, accessToken: String?,
                            progress: @escaping @Sendable (Int) -> Void) async throws {
        let target = place(vaultId, fileId)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: file, to: target)
        progress((try? VaultFileCipher.byteCount(of: target)) ?? 0)
    }

    public func downloadLarge(vaultId: String, fileId: String, to file: URL, expectedBytes: Int?, accessToken: String?,
                              progress: @escaping @Sendable (Int) -> Void) async throws {
        let source = place(vaultId, fileId)
        guard FileManager.default.fileExists(atPath: source.path) else { throw VaultError.notFound(path: fileId) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: source, to: file)
        progress((try? VaultFileCipher.byteCount(of: file)) ?? 0)
    }
}
