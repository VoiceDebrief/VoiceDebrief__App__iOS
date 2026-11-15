import Foundation

/// Where each file goes when files and folders are moved to another folder: worked out first, so that the
/// whole move is one commit and a clash is known before anything is written.
struct MovePlan: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let from: String
        let to: String
    }

    let steps: [Step]
    /// Names that would land on a file already there, when clashes are not renamed.
    let clashes: [String]
    let destination: String

    /// - Parameters:
    ///   - files: paths of single files chosen.
    ///   - folders: paths of folders chosen; everything beneath them moves, keeping its shape.
    ///   - all: every path in the vault now.
    ///   - rename: give a clashing file the next free name ("photo 2.jpg") rather than refuse.
    static func make(files: [String], folders: [String], to destination: String, all: [String], rename: Bool) -> MovePlan {
        let dest = destination.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var wanted: [(from: String, to: String)] = []
        for path in files {
            wanted.append((path, join(dest, VaultListing.name(of: path))))
        }
        for folder in folders {
            let base = VaultListing.name(of: folder)
            for path in all where path.hasPrefix(folder + "/") {
                wanted.append((path, join(dest, join(base, String(path.dropFirst(folder.count + 1))))))
            }
        }
        // A folder cannot go inside itself, and a file already where it is going stays.
        wanted = wanted.filter { item in
            !folders.contains { dest == $0 || dest.hasPrefix($0 + "/") } && item.from != item.to
        }
        let moving = Set(wanted.map(\.from))
        var taken = all.filter { !moving.contains($0) }
        var steps: [Step] = []
        var clashes: [String] = []
        for item in wanted {
            var target = item.to
            if taken.contains(target) {
                if rename {
                    target = VaultNaming.paths(for: [VaultListing.name(of: target)], in: VaultListing.parent(of: target), existing: taken)[0]
                } else {
                    clashes.append(VaultListing.name(of: target))
                    continue
                }
            }
            taken.append(target)
            steps.append(Step(from: item.from, to: target))
        }
        return MovePlan(steps: steps, clashes: clashes, destination: dest)
    }

    /// "Move 12 files to photos/day-2", "Move IMG_1.jpg to the top of the vault".
    var message: String {
        let place = destination.isEmpty ? "the top of the vault" : destination
        let what = steps.count == 1 ? VaultListing.name(of: steps[0].from) : "\(steps.count) files"
        return VaultNaming.fit("Move \(what) to \(place)")
    }

    private static func join(_ a: String, _ b: String) -> String { a.isEmpty ? b : (b.isEmpty ? a : a + "/" + b) }
}
