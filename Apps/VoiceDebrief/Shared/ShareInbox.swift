import Foundation

/// The folder that the share extension and the app both own (the App Group `group.ai.voicedebrief`), and
/// the voice notes waiting in it.
///
/// The extension copies a shared file in, file to file, with a small JSON record beside it, and closes. The
/// app takes each one into its library as a note and only then removes it from here, so a file is never lost
/// between the two: if anything stops half way, it is still waiting the next time the app opens.
///
/// Layout: `inbox/<id>/parcel.json` and `inbox/<id>/<file>`. A parcel is written into `inbox/<id>.partial/`
/// and renamed when complete, so the app never sees half of one.
struct ShareParcel: Codable, Equatable, Sendable {
    static let format = "voicedebrief.ai/share-parcel/v1"

    var format: String = ShareParcel.format
    var id: String
    /// The file's name in the parcel's folder.
    var fileName: String
    /// The name it had where it came from (WhatsApp's own, for example).
    var originalName: String
    /// The type the sending app gave it, such as `org.xiph.opus` or `public.mpeg-4-audio`.
    var typeIdentifier: String
    var bytes: Int
    /// The length in seconds, if the extension could tell.
    var seconds: Double?
    var receivedAt: Date
}

struct ShareInbox: Sendable {
    static let appGroup = "group.ai.voicedebrief"
    /// Posted (a Darwin notification, no payload) by the extension when a parcel is complete, so that an app
    /// already running takes it at once.
    static let darwinNotification = "ai.voicedebrief.share.parcel"

    let root: URL

    init(root: URL) { self.root = root }

    /// The inbox in the App Group container; nil when this build is not entitled to the group (unsigned, or
    /// signed before the group was registered).
    static func shared() -> ShareInbox? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        return ShareInbox(root: container.appending(path: "inbox", directoryHint: .isDirectory))
    }

    private func folder(_ id: String) -> URL { root.appending(path: id, directoryHint: .isDirectory) }

    static func newId(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date) + "-" + UUID().uuidString.lowercased().prefix(8)
    }

    /// A file name that is safe on disk, keeping the extension (WhatsApp's names can hold anything).
    static func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        var cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if cleaned.isEmpty { cleaned = "voice-note" }
        return String(cleaned.suffix(120))
    }

    /// Copies the file at `source` into a new parcel and writes its record. The source is not touched.
    @discardableResult
    func keep(fileAt source: URL, originalName: String, typeIdentifier: String, seconds: Double?,
              now: Date = Date()) throws -> ShareParcel {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let id = Self.newId(at: now)
        let partial = root.appending(path: id + ".partial", directoryHint: .isDirectory)
        try? manager.removeItem(at: partial)
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            let fileName = Self.safeName(originalName.isEmpty ? source.lastPathComponent : originalName)
            let target = partial.appending(path: fileName)
            try manager.copyItem(at: source, to: target)
            let size = (try? manager.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
            let parcel = ShareParcel(id: id, fileName: fileName, originalName: originalName,
                                     typeIdentifier: typeIdentifier, bytes: size, seconds: seconds, receivedAt: now)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(parcel).write(to: partial.appending(path: "parcel.json"), options: .atomic)
            try manager.moveItem(at: partial, to: folder(id))
            return parcel
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    /// Every complete parcel, oldest first, with its file. A folder without a readable record, or whose file
    /// is missing, is left alone (and not listed): it is never deleted by guesswork.
    func waiting() -> [(parcel: ShareParcel, file: URL)] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [(parcel: ShareParcel, file: URL)] = []
        for folder in folders where !folder.lastPathComponent.hasSuffix(".partial") {
            guard let data = try? Data(contentsOf: folder.appending(path: "parcel.json")),
                  let parcel = try? decoder.decode(ShareParcel.self, from: data),
                  parcel.format == ShareParcel.format else { continue }
            let file = folder.appending(path: parcel.fileName)
            guard manager.fileExists(atPath: file.path) else { continue }
            found.append((parcel: parcel, file: file))
        }
        return found.sorted {
            $0.parcel.receivedAt < $1.parcel.receivedAt
                || ($0.parcel.receivedAt == $1.parcel.receivedAt && $0.parcel.id < $1.parcel.id)
        }
    }

    /// Removes a parcel once its note exists.
    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Tells a running app that a parcel is waiting.
    static func announce() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(darwinNotification as CFString), nil, nil, true)
    }
}
