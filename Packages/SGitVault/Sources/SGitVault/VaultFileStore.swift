import Foundation

// A vault as one file (the SGit Secrets design: website/articles/secrets-app/, section 5).
//
//   VaultArchive     a vault folder (the server's layout: bare/data, bare/refs, bare/indexes, bare/keys)
//                    written as one *stored* zip, and read back with every name, size and checksum checked.
//                    Stored, not deflated: the objects are already encrypted and do not shrink.
//   VaultObjects     the union of two vault folders' objects: what the destination lacks is copied, each
//                    content-addressed object checked against its id first. Refs and indexes are left alone;
//                    moving a head is a merge's job.
//   VaultFileStore   one vault file replaced atomically, with its earlier copies kept in a folder of its own
//                    (`.versions/<file name>/`), the oldest beyond `keep` removed.
//
// A plain `unzip` gives back the folder, which `sgit clone --transport local --base-url <folder>` opens.

/// Why an archive or a file store refused something. Never contains key material.
public enum VaultArchiveError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The bytes are not a zip this reader accepts (truncated, a missing record, or a feature it does not use).
    case notAnArchive(String)
    /// An entry's name is not a plain vault path: absolute, `..`, a backslash, a NUL, outside `bare/…`.
    case unsafeName(String)
    /// An entry is a symbolic link, a directory where a file belongs, or uses compression or encryption.
    case unsupportedEntry(String)
    /// The same name twice.
    case duplicateName(String)
    /// An entry's checksum or size does not match its record.
    case damaged(String)
    /// More entries or bytes than the reader accepts.
    case tooLarge(String)
    /// A content-addressed object does not hash to its id.
    case integrity(String)
    /// The folder to unpack into already holds files.
    case destinationNotEmpty(String)

    public var description: String {
        switch self {
        case .notAnArchive(let d): return "not a vault archive: \(d)"
        case .unsafeName(let n): return "unsafe name in archive: \(n.debugDescription)"
        case .unsupportedEntry(let n): return "unsupported entry in archive: \(n.debugDescription)"
        case .duplicateName(let n): return "name twice in archive: \(n)"
        case .damaged(let n): return "damaged entry in archive: \(n)"
        case .tooLarge(let d): return "archive too large: \(d)"
        case .integrity(let n): return "object does not match its id: \(n)"
        case .destinationNotEmpty(let p): return "folder is not empty: \(p)"
        }
    }
}

// MARK: - The archive

public enum VaultArchive {
    /// The folders an archive may hold, each flat: one level of files, no subfolders.
    public static let folders = ["bare/data", "bare/refs", "bare/indexes", "bare/keys"]
    /// No zip64: at most 65,535 entries and 4 GB. A vault of secrets is far smaller.
    public static let maxEntries = 65_535
    public static let maxEntryBytes = 64 * 1024 * 1024
    public static let maxTotalBytes = 1024 * 1024 * 1024

    struct Entry: Equatable {
        var name: String
        var data: Data
        /// Unix mode in the central directory's external attributes; regular file 0o100644.
        var mode: UInt32 = 0o100644
    }

    // MARK: Writing

    /// The vault folder at `folder` (which contains `bare/`) as one archive. The same folder always gives
    /// the same bytes: names in order, a fixed date, no extra fields.
    public static func archive(folder: URL) throws -> Data {
        var entries: [Entry] = []
        let manager = FileManager.default
        for sub in folders {
            let dir = folder.appending(path: sub, directoryHint: .isDirectory)
            guard let names = try? manager.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let url = dir.appending(path: name)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw VaultArchiveError.unsupportedEntry("\(sub)/\(name)")
                }
                let path = "\(sub)/\(name)"
                try checkName(path)
                entries.append(Entry(name: path, data: try Data(contentsOf: url)))
            }
        }
        return try zip(entries)
    }

    /// Writes the archive of `folder` to `url` (replacing any file there).
    public static func write(folder: URL, to url: URL) throws {
        try archive(folder: folder).write(to: url, options: .atomic)
    }

    /// A stored zip of `entries`, in the order given. Internal so that tests can build hostile archives.
    static func zip(_ entries: [Entry]) throws -> Data {
        guard entries.count <= maxEntries else { throw VaultArchiveError.tooLarge("\(entries.count) entries") }
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            guard entry.data.count <= maxEntryBytes, name.count <= 0xFFFF else {
                throw VaultArchiveError.tooLarge(entry.name)
            }
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(out.count)
            // Local file header.
            out.le32(0x0403_4B50); out.le16(20); out.le16(0x0800)   // version 2.0; names are UTF-8
            out.le16(0)                                              // stored
            out.le16(0); out.le16(0x0021)                            // 1 January 1980, 00:00
            out.le32(crc); out.le32(UInt32(entry.data.count)); out.le32(UInt32(entry.data.count))
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(entry.data)
            // Central directory record.
            central.le32(0x0201_4B50); central.le16(0x0314)          // made by Unix, version 2.0
            central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(0); central.le16(0x0021)
            central.le32(crc); central.le32(UInt32(entry.data.count)); central.le32(UInt32(entry.data.count))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0)
            central.le32(entry.mode << 16); central.le32(offset)
            central.append(name)
            guard out.count <= maxTotalBytes else { throw VaultArchiveError.tooLarge("more than \(maxTotalBytes) bytes") }
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset); out.le16(0)
        return out
    }

    // MARK: Reading

    /// Every entry of an archive, after checking each name, record, size and checksum, and each
    /// content-addressed object against its id. Nothing is written anywhere.
    static func entries(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw VaultArchiveError.notAnArchive("too short") }
        // The end of central directory record: within the last 22 + 65,535 bytes (a comment may follow it).
        var end = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while i >= lowest {
            if bytes.u32(i) == 0x0605_4B50 { end = i; break }
            i -= 1
        }
        guard end >= 0 else { throw VaultArchiveError.notAnArchive("no end record") }
        guard bytes.u16(end + 4) == 0, bytes.u16(end + 6) == 0 else { throw VaultArchiveError.notAnArchive("split archive") }
        let count = Int(bytes.u16(end + 10))
        guard Int(bytes.u16(end + 8)) == count else { throw VaultArchiveError.notAnArchive("entry counts differ") }
        let centralSize = Int(bytes.u32(end + 12)), centralOffset = Int(bytes.u32(end + 16))
        guard centralOffset + centralSize <= end else { throw VaultArchiveError.notAnArchive("central directory out of range") }

        var out: [Entry] = []
        var seen = Set<String>()
        var total = 0
        var p = centralOffset
        for _ in 0..<count {
            guard p + 46 <= end, bytes.u32(p) == 0x0201_4B50 else { throw VaultArchiveError.notAnArchive("bad central record") }
            let madeBy = bytes.u16(p + 4)
            let flags = bytes.u16(p + 8), method = bytes.u16(p + 10)
            let crc = bytes.u32(p + 16)
            let packed = Int(bytes.u32(p + 20)), size = Int(bytes.u32(p + 24))
            let nameLength = Int(bytes.u16(p + 28)), extraLength = Int(bytes.u16(p + 30)), commentLength = Int(bytes.u16(p + 32))
            let external = bytes.u32(p + 38)
            let localOffset = Int(bytes.u32(p + 42))
            guard p + 46 + nameLength + extraLength + commentLength <= end else { throw VaultArchiveError.notAnArchive("record out of range") }
            let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLength)])
            p += 46 + nameLength + extraLength + commentLength

            guard !nameBytes.contains(0) else { throw VaultArchiveError.unsafeName(String(decoding: nameBytes, as: UTF8.self)) }
            guard let name = String(bytes: nameBytes, encoding: .utf8) else { throw VaultArchiveError.unsafeName("not UTF-8") }
            try checkName(name)
            let unixMode = madeBy >> 8 == 3 ? external >> 16 : 0
            let fileType = unixMode & 0o170000
            guard fileType == 0 || fileType == 0o100000 else { throw VaultArchiveError.unsupportedEntry(name) }   // symlinks, folders
            guard flags & 0x0001 == 0 else { throw VaultArchiveError.unsupportedEntry(name) }                       // encrypted
            guard method == 0, packed == size else { throw VaultArchiveError.unsupportedEntry(name) }               // stored only
            guard !seen.contains(name) else { throw VaultArchiveError.duplicateName(name) }
            seen.insert(name)
            guard size <= maxEntryBytes else { throw VaultArchiveError.tooLarge(name) }
            total += size
            guard total <= maxTotalBytes, out.count < maxEntries else { throw VaultArchiveError.tooLarge("more than the reader accepts") }

            // The local header must agree with the central record.
            let l = localOffset
            guard l + 30 <= centralOffset, bytes.u32(l) == 0x0403_4B50 else { throw VaultArchiveError.damaged(name) }
            let localNameLength = Int(bytes.u16(l + 26)), localExtra = Int(bytes.u16(l + 28))
            let start = l + 30 + localNameLength + localExtra
            guard start + size <= centralOffset,
                  Array(bytes[(l + 30)..<(l + 30 + localNameLength)]) == nameBytes,
                  bytes.u16(l + 8) == 0 else { throw VaultArchiveError.damaged(name) }
            let content = Data(bytes[start..<(start + size)])
            guard CRC32.checksum(content) == crc else { throw VaultArchiveError.damaged(name) }
            try checkObject(name, content)
            out.append(Entry(name: name, data: content, mode: unixMode == 0 ? 0o100644 : unixMode))
        }
        return out
    }

    /// Unpacks an archive into `folder`, which must not exist or be empty. Everything is checked before
    /// the first file is written, so a refused archive leaves nothing behind. Returns the paths written.
    @discardableResult
    public static func read(_ data: Data, into folder: URL) throws -> [String] {
        let all = try entries(data)
        let manager = FileManager.default
        if let existing = try? manager.contentsOfDirectory(atPath: folder.path), !existing.isEmpty {
            throw VaultArchiveError.destinationNotEmpty(folder.lastPathComponent)
        }
        for sub in folders {
            try manager.createDirectory(at: folder.appending(path: sub, directoryHint: .isDirectory),
                                        withIntermediateDirectories: true)
        }
        for entry in all {
            try entry.data.write(to: folder.appending(path: entry.name), options: .withoutOverwriting)
        }
        return all.map(\.name)
    }

    /// A name is `<one of folders>/<plain file name>`: letters, digits, `.`, `_` and `-`, not starting with a dot.
    static func checkName(_ name: String) throws {
        guard !name.contains("\\"), !name.contains("\0"), !name.hasPrefix("/") else { throw VaultArchiveError.unsafeName(name) }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw VaultArchiveError.unsafeName(name)
        }
        guard folders.contains("\(parts[0])/\(parts[1])") else { throw VaultArchiveError.unsafeName(name) }
        let file = parts[2]
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard file.count <= 200, !file.hasPrefix("."), file.allSatisfy({ allowed.contains($0) }) else {
            throw VaultArchiveError.unsafeName(name)
        }
    }

    /// A content-addressed object (`bare/data/obj-cas-imm-…`) must hash to its id.
    static func checkObject(_ name: String, _ data: Data) throws {
        let prefix = "bare/data/" + VaultCrypto.objectPrefix
        guard name.hasPrefix(prefix) else { return }
        let id = String(name.dropFirst("bare/data/".count))
        guard VaultCrypto.objectIdWidth(id) > 0, VaultCrypto.objectIdMatches(id, ciphertext: data) else {
            throw VaultArchiveError.integrity(id)
        }
    }
}

// MARK: - The union of two vault folders

public enum VaultObjects {
    public struct Union: Equatable, Sendable {
        /// Paths copied into the destination.
        public var added: [String]
        /// Paths the destination already held with the same bytes (or, for content-addressed objects, the same id).
        public var alreadyPresent: Int
        /// Paths both held with different bytes (only possible for files that are not content-addressed).
        /// The destination's copy is kept.
        public var differing: [String]
    }

    /// Copies into `destination` the objects and public keys of `source` that it lacks. Every
    /// content-addressed object to be copied is checked against its id before anything is copied, so a
    /// tampered source changes nothing. Refs and indexes are not touched.
    @discardableResult
    public static func union(from source: URL, into destination: URL) throws -> Union {
        let manager = FileManager.default
        var plan: [(path: String, data: Data)] = []
        var present = 0
        var differing: [String] = []
        for sub in ["bare/data", "bare/keys"] {
            let from = source.appending(path: sub, directoryHint: .isDirectory)
            guard let names = try? manager.contentsOfDirectory(atPath: from.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = "\(sub)/\(name)"
                try VaultArchive.checkName(path)
                let target = destination.appending(path: path)
                let data = try Data(contentsOf: from.appending(path: name))
                if manager.fileExists(atPath: target.path) {
                    if name.hasPrefix(VaultCrypto.objectPrefix) || (try? Data(contentsOf: target)) == data {
                        present += 1
                    } else {
                        differing.append(path)
                    }
                    continue
                }
                try VaultArchive.checkObject(path, data)
                plan.append((path, data))
            }
        }
        for sub in ["bare/data", "bare/keys"] {
            try manager.createDirectory(at: destination.appending(path: sub, directoryHint: .isDirectory),
                                        withIntermediateDirectories: true)
        }
        for item in plan {
            try item.data.write(to: destination.appending(path: item.path), options: [.atomic, .withoutOverwriting])
        }
        return Union(added: plan.map(\.path), alreadyPresent: present, differing: differing)
    }
}

// MARK: - One file, replaced atomically, with earlier copies

public struct VaultFileStore: Sendable {
    /// The vault file, for example `…/My secrets.sgvault`.
    public let file: URL
    /// How many earlier copies to keep.
    public let keep: Int
    /// Names this device in the earlier copies' file names: letters, digits and hyphens, at most 32.
    public let device: String

    public init(file: URL, keep: Int = 5, device: String) {
        self.file = file
        self.keep = max(0, keep)
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let cleaned = String(device.map { allowed.contains($0) ? $0 : "-" }.prefix(32))
        self.device = cleaned.isEmpty ? "device" : cleaned
    }

    /// The folder that holds this file's earlier copies, and nothing else: `.versions/<file name>/`.
    public var versionsFolder: URL {
        file.deletingLastPathComponent()
            .appending(path: ".versions", directoryHint: .isDirectory)
            .appending(path: file.lastPathComponent, directoryHint: .isDirectory)
    }

    /// The earlier copies, oldest first (their names start with a UTC time, so name order is time order).
    public func earlierCopies() throws -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versionsFolder.path)) ?? []
        return names.filter(isCopyName).sorted().map { versionsFolder.appending(path: $0) }
    }

    /// The file's bytes, read through a file coordinator (so that iCloud has finished with it), or nil.
    public func read() throws -> Data? {
        var result: Result<Data?, Error> = .success(nil)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            result = Result {
                FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Replaces the file with `data` in one step, so that a reader sees the old file or the new one and
    /// never a part. The old file is first copied into the versions folder; copies beyond `keep` are then
    /// removed, oldest first, from that folder only.
    public func replace(with data: Data, at date: Date = Date()) throws {
        var result: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try replaceNow(at: url, with: data, date: date) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    func replaceNow(at url: URL, with data: Data, date: Date) throws {
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path), keep > 0 {
            try manager.createDirectory(at: versionsFolder, withIntermediateDirectories: true)
            try manager.copyItem(at: url, to: freeCopyURL(at: date))
        }
        let temporary = parent.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
        try prune()
    }

    /// Removes the oldest copies beyond `keep`. Only names this store writes, only in its own folder.
    func prune() throws {
        let copies = try earlierCopies()
        guard copies.count > keep else { return }
        let own = versionsFolder.standardizedFileURL.path
        for url in copies.prefix(copies.count - keep) where url.deletingLastPathComponent().standardizedFileURL.path == own {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// `2026-11-15T23-10-15Z <device>.<ext>`, with `-2`, `-3`… after the time if that name is taken.
    func freeCopyURL(at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let stamp = formatter.string(from: date)
        let ext = file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)"
        var n = 1
        while true {
            let name = n == 1 ? "\(stamp) \(device)\(ext)" : "\(stamp)-\(n) \(device)\(ext)"
            let url = versionsFolder.appending(path: name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// Whether a name in the versions folder is one this store wrote.
    func isCopyName(_ name: String) -> Bool {
        let ext = file.pathExtension.isEmpty ? "" : ".\(file.pathExtension)"
        guard name.count >= 21, name.hasSuffix(ext), !name.hasPrefix(".") else { return false }
        let stamp = name.prefix(20)
        let pattern = Array("dddd-dd-ddTdd-dd-ddZ")
        for (c, want) in zip(stamp, pattern) {
            if want == "d" { guard c.isASCII, c.isNumber else { return false } } else if c != want { return false }
        }
        return true
    }
}

// MARK: - Helpers

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(shift)) & 0xFF)) } }
}

private extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24 }
}
