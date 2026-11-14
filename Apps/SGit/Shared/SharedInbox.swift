import Foundation

/// What the share extension leaves for the app, in a folder both own (an App Group container).
///
/// The extension cannot encrypt or upload: it has little memory and a short life. It copies what it
/// was given into a parcel here, file to file, and closes. The app turns each parcel into an outbox
/// job when it is next opened. No key is ever written here: only the names and ids of the vaults,
/// so that the extension can offer a choice.
enum SharedInbox {
    static let group = "group.ai.sgit.vaults.app"

    /// A vault as the extension may know it: enough to choose one, nothing that opens it.
    struct Listed: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var canWrite: Bool
    }

    /// One act of sharing: the files, and where they are to go.
    struct Parcel: Codable, Identifiable, Hashable, Sendable {
        var id: UUID
        var vaultId: String
        var folder: String
        var createdAt: Date
        /// The names the files are to have in the vault, in order. File `n` is stored as `files/<n>`.
        var names: [String]
    }

    /// The shared folder, or nil where the app has no App Group (an unsigned build, a test).
    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: "inbox", directoryHint: .isDirectory)
    }

    static func vaultList(in root: URL) -> URL { root.appending(path: "vaults.json") }
    static func parcels(in root: URL) -> URL { root.appending(path: "parcels", directoryHint: .isDirectory) }

    /// The app writes the list of vaults each time it changes.
    static func publish(_ vaults: [Listed], in root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(vaults) else { return }
        try? data.write(to: vaultList(in: root), options: .atomic)
    }

    static func listed(in root: URL) -> [Listed] {
        guard let data = try? Data(contentsOf: vaultList(in: root)) else { return [] }
        return (try? JSONDecoder().decode([Listed].self, from: data)) ?? []
    }

    /// Keeps files as a parcel. The record is written last, so a parcel that was cut short is never
    /// read as whole. Returns the parcel, or throws and leaves nothing behind.
    @discardableResult
    static func keep(_ files: [(url: URL, name: String)], vaultId: String, folder: String, in root: URL) throws -> Parcel {
        let parcel = Parcel(id: UUID(), vaultId: vaultId, folder: folder, createdAt: Date(), names: files.map(\.name))
        let home = parcels(in: root).appending(path: parcel.id.uuidString, directoryHint: .isDirectory)
        let store = home.appending(path: "files", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
            for (index, file) in files.enumerated() {
                try FileManager.default.copyItem(at: file.url, to: store.appending(path: String(index)))
            }
            try JSONEncoder().encode(parcel).write(to: home.appending(path: "parcel.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: home)
            throw error
        }
        return parcel
    }

    /// The whole parcels waiting, oldest first.
    static func waiting(in root: URL) -> [Parcel] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: parcels(in: root), includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> Parcel? in
            guard let data = try? Data(contentsOf: folder.appending(path: "parcel.json")) else { return nil }
            return try? JSONDecoder().decode(Parcel.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func file(_ index: Int, of parcel: Parcel, in root: URL) -> URL {
        parcels(in: root).appending(path: parcel.id.uuidString, directoryHint: .isDirectory)
            .appending(path: "files", directoryHint: .isDirectory).appending(path: String(index))
    }

    static func remove(_ parcel: Parcel, in root: URL) {
        try? FileManager.default.removeItem(at: parcels(in: root).appending(path: parcel.id.uuidString, directoryHint: .isDirectory))
    }
}
