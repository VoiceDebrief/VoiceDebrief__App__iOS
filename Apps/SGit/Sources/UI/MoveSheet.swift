import SGitVault
import SwiftUI

/// Where chosen files and folders go: any folder in the vault, the top, or a new one. One commit.
struct MoveSheet: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let files: [VaultFile]
    let folders: [String]
    let done: () -> Void
    @State private var newFolder = ""
    @State private var working = false
    @State private var problem: String?
    @State private var clash: (destination: String, names: [String])?
    @Environment(\.dismiss) private var dismiss

    /// Every folder that holds a file, without the ones being moved or anything inside them.
    private var destinations: [String] {
        let paths = VaultListing.visible(shelf.contents[vault.id]?.files ?? []).map(\.path)
        var found = Set<String>()
        for path in paths {
            var parent = VaultListing.parent(of: path)
            while !parent.isEmpty {
                found.insert(parent)
                parent = VaultListing.parent(of: parent)
            }
        }
        return found.filter { place in !folders.contains { place == $0 || place.hasPrefix($0 + "/") } }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var count: Int {
        let all = shelf.contents[vault.id]?.files ?? []
        return files.count + folders.reduce(0) { total, folder in total + all.filter { $0.path.hasPrefix(folder + "/") }.count }
    }

    var body: some View {
        List {
            Section {
                Text("\(count) file\(count == 1 ? "" : "s") will move in one change, kept with their history. Nothing is uploaded again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("A new folder") {
                TextField("Name, such as photos/day-2", text: $newFolder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Move here") { Task { await move(to: newFolder, rename: false) } }
                    .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            Section("A folder already in the vault") {
                Button { Task { await move(to: "", rename: false) } } label: {
                    Label("The top of the vault", systemImage: "tray")
                }
                ForEach(destinations, id: \.self) { place in
                    Button { Task { await move(to: place, rename: false) } } label: {
                        Label(place.replacingOccurrences(of: "/", with: " / "), systemImage: "folder")
                    }
                }
            }
            .disabled(working)
            if working { Section { HStack { ProgressView(); Text("Moving") } } }
            if let problem { Section { ProblemLabel(text: problem) } }
        }
        .navigationTitle("Move to")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .confirmationDialog("Some names are taken there", isPresented: Binding(get: { clash != nil }, set: { if !$0 { clash = nil } }),
                            titleVisibility: .visible) {
            if let clash {
                Button("Move, giving those a new name") { Task { await move(to: clash.destination, rename: true) } }
            }
            Button("Do not move", role: .cancel) {}
        } message: {
            Text("The folder already has " + (clash?.names.prefix(3).joined(separator: ", ") ?? "") + ". Nothing is overwritten: the moved ones can take the next free name, such as \"photo 2.jpg\".")
        }
    }

    private func move(to destination: String, rename: Bool) async {
        working = true
        defer { working = false }
        problem = nil
        let place = VaultNaming.cleanFolder(destination)
        do {
            try await shelf.move(files: files, folders: folders, to: place, in: vault, renameClashes: rename)
            done()
            dismiss()
        } catch VaultShelfError.moveClash(let names) {
            clash = (place, names)
        } catch {
            problem = VaultShelf.describe(error)
        }
    }
}
