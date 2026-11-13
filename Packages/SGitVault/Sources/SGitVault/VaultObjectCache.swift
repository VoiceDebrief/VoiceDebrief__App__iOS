import Foundation

/// The on-disk cache of immutable vault objects (`obj-cas-imm-*` and `key-rnd-imm-*`).
///
/// - Stores **ciphertext** only, exactly as the server returned it; nothing decrypted touches disk here.
/// - Objects are content-addressed and never change, so they are kept forever.
/// - Refs and the branch index are mutable and are **never** cached.
/// - Owned by one `SGitVault` actor; not shared across actors.
final class VaultObjectCache {
    let directory: URL
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var bytesServed = 0

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Only immutable names are cacheable.
    static func isCacheable(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name.hasPrefix("obj-cas-imm-") || name.hasPrefix("key-rnd-imm-")
    }

    private func fileURL(_ path: String) -> URL {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return directory.appending(path: name)
    }

    func load(_ path: String) -> Data? {
        guard Self.isCacheable(path), let data = try? Data(contentsOf: fileURL(path)) else {
            misses += 1
            return nil
        }
        hits += 1
        bytesServed += data.count
        return data
    }

    func store(_ data: Data, for path: String) {
        guard Self.isCacheable(path) else { return }
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)   // background refresh can read it
        #endif
        try? data.write(to: fileURL(path), options: options)
    }

    func remove(_ path: String) {
        try? FileManager.default.removeItem(at: fileURL(path))
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hits = 0
        misses = 0
        bytesServed = 0
    }

    func stats() -> VaultCacheStats {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return VaultCacheStats(objects: files.count, bytes: bytes, hits: hits, misses: misses,
                               bytesServed: bytesServed, directory: directory.lastPathComponent)
    }
}

public struct VaultCacheStats: Sendable, Hashable, Codable {
    public let objects: Int
    public let bytes: Int
    public let hits: Int
    public let misses: Int
    public let bytesServed: Int
    /// The folder name, not the full path.
    public let directory: String
    public var hitRate: Double { hits + misses == 0 ? 0 : Double(hits) / Double(hits + misses) }
}
