import Foundation
import SGitVault

/// One folder of a vault, as the browser shows it: the folders directly inside, then the files.
struct VaultListing: Equatable, Sendable {
    struct Folder: Identifiable, Hashable, Sendable {
        var id: String { path }
        let name: String
        let path: String
        let files: Int
        let bytes: Int
    }

    let folder: String
    let folders: [Folder]
    let files: [VaultFile]

    /// - Parameter folder: "" for the top of the vault, else a path without a trailing slash.
    static func of(_ all: [VaultFile], in folder: String) -> VaultListing {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var folders: [String: (files: Int, bytes: Int)] = [:]
        var files: [VaultFile] = []
        for file in all where file.path.hasPrefix(prefix) {
            let rest = file.path.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                let name = String(rest[..<slash])
                let held = folders[name] ?? (0, 0)
                folders[name] = (held.files + 1, held.bytes + file.size)
            } else if !rest.isEmpty {
                files.append(file)
            }
        }
        let sortedFolders = folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            Folder(name: name, path: prefix + name, files: folders[name]?.files ?? 0, bytes: folders[name]?.bytes ?? 0)
        }
        files.sort { name(of: $0.path).localizedStandardCompare(name(of: $1.path)) == .orderedAscending }
        return VaultListing(folder: folder, folders: sortedFolders, files: files)
    }

    /// A folder in the tree shown beside the files on a wide screen.
    struct Node: Identifiable, Hashable, Sendable {
        var id: String { path }
        let name: String
        let path: String
        /// Nil when the folder holds no folders, so that no disclosure arrow is drawn.
        var children: [Node]?
    }

    /// Every folder the paths imply, as a tree, sorted as the Finder sorts.
    static func tree(paths: [String]) -> [Node] {
        var found: Set<String> = []
        for path in paths {
            var parts = path.split(separator: "/").map(String.init)
            parts.removeLast()
            var here = ""
            for part in parts {
                here = here.isEmpty ? part : here + "/" + part
                found.insert(here)
            }
        }
        let folders = found
        func below(_ parent: String) -> [Node]? {
            let direct = folders.filter { Self.parent(of: $0) == parent }
                .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
            guard !direct.isEmpty else { return nil }
            return direct.map { Node(name: name(of: $0), path: $0, children: below($0)) }
        }
        return below("") ?? []
    }

    static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// What kind of thing a file is, from its name: decides the icon and the viewer.
    enum Kind: Sendable { case image, video, audio, document }

    static func kind(of path: String) -> Kind {
        let ext = name(of: path).split(separator: ".").last.map { $0.lowercased() } ?? ""
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp"].contains(ext) { return .image }
        if ["mov", "mp4", "m4v", "avi", "webm"].contains(ext) { return .video }
        if ["m4a", "mp3", "wav", "aac"].contains(ext) { return .audio }
        return .document
    }
}

/// Names for files going into a vault.
enum VaultNaming {
    /// A name safe to use as one path component: no slashes, no leading dot, not empty.
    static func clean(_ name: String) -> String {
        var out = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        return out.isEmpty ? "file" : out
    }

    /// A folder path as typed, made safe: "a//b/ " becomes "a/b".
    static func cleanFolder(_ text: String) -> String {
        text.split(separator: "/").map { clean(String($0)) }.joined(separator: "/")
    }

    /// `name`, or `name 2`, `name 3`… before the extension, whichever is not in `taken`.
    static func unique(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var stem = name
        var ext = ""
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            stem = String(name[..<dot])
            ext = String(name[dot...])
        }
        var n = 2
        while taken.contains("\(stem) \(n)\(ext)") { n += 1 }
        return "\(stem) \(n)\(ext)"
    }

    /// The paths a selection gets in `folder`, in order, none colliding with `existing` or each other.
    static func paths(for names: [String], in folder: String, existing: [String]) -> [String] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var taken = Set(existing.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
            .map { String($0.dropFirst(prefix.count)) })
        var out: [String] = []
        for name in names {
            let chosen = unique(clean(name), taken: taken)
            taken.insert(chosen)
            out.append(prefix + chosen)
        }
        return out
    }

    /// The commit message, in the web Vault UI's words: `Add a.jpg`, `Add 3 files: a, b, c`.
    static func addMessage(_ names: [String]) -> String {
        guard names.count != 1 else { return fit("Add \(names[0])") }
        let shown = names.prefix(3).joined(separator: ", ")
        return fit("Add \(names.count) files: \(shown)\(names.count > 3 ? "…" : "")")
    }

    /// sgit refuses a message over 740 bytes on most vaults.
    static func fit(_ message: String) -> String {
        var out = message
        while out.utf8.count > 700 { out.removeLast() }
        return out
    }

    /// The key in a pasted or scanned text: a key as it is, or the fragment of a web Vault link
    /// (`https://vault.sgraph.ai/#passphrase:vaultid|path`).
    static func keyText(from scanned: String) -> String {
        let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("http"), let hash = text.firstIndex(of: "#") else { return text }
        var fragment = String(text[text.index(after: hash)...])
        if let bar = fragment.firstIndex(of: "|") { fragment = String(fragment[..<bar]) }
        return fragment.removingPercentEncoding ?? fragment
    }

    /// A vault's standing, in words a person needs: where it is and what this device may do with it.
    static func standing(canWrite: Bool, onDevice: Bool) -> String {
        if onDevice { return "Only on this device" }
        return canWrite ? "Shared: you can add and change" : "Shared: you can look, not change"
    }

    /// Where a vault's contents stand, for the line at the top of its screen.
    static func arrival(onDevice: Bool, server: String, pendingFiles: Int, failed: Bool, checked: Date?, now: Date = Date()) -> String {
        if failed { return "Some files did not go in. They are kept here: try again below." }
        if pendingFiles > 0 {
            return "\(pendingFiles) file\(pendingFiles == 1 ? "" : "s") on \(pendingFiles == 1 ? "its" : "their") way in. Keep the app open."
        }
        if onDevice { return "Everything here is on this device only." }
        guard let checked else { return "On \(server)." }
        let seconds = Int(now.timeIntervalSince(checked))
        let when = seconds < 90 ? "just now" : seconds < 3_600 ? "\(seconds / 60) minutes ago" : "more than an hour ago"
        return "Everything here is on \(server). Checked \(when)."
    }

    /// What is sent to somebody being given a vault: the steps, then the key, then a link for a browser.
    static func invitation(name: String, keyText: String, readOnly: Bool, server: String) -> String {
        var lines = ["\(name): a vault of files, encrypted so that only people with its key can open it.", "",
                     "To open it in the sgit app: choose \"Add a vault by its key\" and paste this key.", "", keyText]
        if let link = webLink(keyText: keyText) {
            lines += ["", "Or open it in a browser:", link]
        }
        lines += ["", readOnly ? "This key lets you look and not change anything."
                               : "This key lets you add, change and delete. To add files you also need an access key for \(server): ask me for one.",
                  "Keep the key to yourself: whoever has it can open the vault, and it cannot be taken back."]
        return lines.joined(separator: "\n")
    }

    /// The link that opens a vault in the web Vault UI. The key is in the fragment, which a browser
    /// does not send to the server.
    static func webLink(keyText: String) -> String? {
        var body = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sgit_private_vault_", "sgit_vk1_"] where body.hasPrefix(prefix) {
            body = String(body.dropFirst(prefix.count))
        }
        guard VaultKey.classify(keyText) == .vault, body.contains(":") else { return nil }
        return AppInfo.webVault + "#" + body
    }

    /// "a1b2 c3d4 e5f6 0718": a fingerprint in groups of four.
    static func grouped(_ fingerprint: String) -> String {
        var out = ""
        for (i, c) in fingerprint.enumerated() {
            if i > 0, i % 4 == 0 { out.append(" ") }
            out.append(c)
        }
        return out
    }
}

extension Int {
    /// "547 B", "12.3 KB", "4.1 MB", "2.37 GB".
    var fileSizeText: String {
        self >= 1_000_000_000 ? String(format: "%.2f GB", Double(self) / 1_000_000_000) : vaultByteString
    }
}
