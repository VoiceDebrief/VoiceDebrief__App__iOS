import AVKit
import QuickLook
import SGitVault
import SwiftUI

/// One file: fetched and decrypted when it is opened, shown, and offered to Photos or another app.
struct FileView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile

    @State private var local: URL?
    @State private var preview: UIImage?
    @State private var player: AVPlayer?
    @State private var fetching = false
    @State private var problem: String?
    @State private var notice: String?
    @State private var quickLook: URL?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    /// Files up to this size are fetched as soon as the screen opens; larger ones wait to be asked.
    static let fetchUnasked = 25_000_000

    private var name: String { VaultListing.name(of: file.path) }
    private var kind: VaultListing.Kind { VaultListing.kind(of: file.path) }

    var body: some View {
        List {
            Section {
                ZStack {
                    if let player {
                        VideoPlayer(player: player).frame(minHeight: 260)
                    } else if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .onTapGesture { quickLook = local }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: FileRow.icon(for: file.path)).font(.system(size: 56)).foregroundStyle(.secondary)
                            if fetching {
                                let got = shelf.fetchedBytes[file.blobId] ?? 0
                                ProgressView(value: min(1, Double(got) / Double(max(file.size, 1))))
                                    .frame(maxWidth: 220)
                                Text("Fetching and decrypting · \(got.fileSizeText) of \(file.size.fileSizeText)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .listRowInsets(EdgeInsets())
            }
            if let problem { Section { ProblemLabel(text: problem) } }
            if let notice { Section { Label(notice, systemImage: "checkmark.circle").font(.callout) } }

            Section {
                if let local {
                    Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { quickLook = local }
                    ShareLink(item: local) { Label("Share", systemImage: "square.and.arrow.up") }
                    if kind == .image || kind == .video {
                        Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { await saveToPhotos(local) } }
                    }
                } else if !fetching {
                    Button("Fetch (\(file.size.fileSizeText))", systemImage: "arrow.down.circle") { Task { await fetch() } }
                }
            } footer: {
                if local != nil {
                    Text("The decrypted copy is in this app's cache on this device. Settings can empty it.")
                }
            }

            Section("Details") {
                LabeledContent("Name", value: name)
                LabeledContent("Folder", value: VaultListing.parent(of: file.path).isEmpty ? "the top of the vault" : VaultListing.parent(of: file.path))
                LabeledContent("Size", value: file.size.fileSizeText)
                if let type = file.contentType, !type.isEmpty { LabeledContent("Type", value: type) }
                LabeledContent("Object", value: String(file.blobId.suffix(12)))
                if file.large { LabeledContent("Stored", value: "as a large object, in parts") }
            }

            if vault.canWrite {
                Section {
                    Button("Rename", systemImage: "pencil") {
                        newName = name
                        renaming = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Each is a signed commit. A deleted file stays in the vault's history.")
                }
                .disabled(working)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($quickLook)
        .task {
            if shelf.isCached(file, in: vault) || file.size <= Self.fetchUnasked { await fetch() }
        }
        .onDisappear { player?.pause() }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await rename() } }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("It is removed from the vault for everybody who has the key. Earlier commits still hold it.")
        }
    }

    private func fetch() async {
        guard local == nil, !fetching else { return }
        fetching = true
        problem = nil
        defer { fetching = false }
        do {
            let url = try await shelf.localFile(for: file, in: vault)
            local = url
            switch kind {
            case .image:
                let data = await Task.detached(priority: .userInitiated) { Thumbnail.jpeg(of: url, maxPixel: 2_400) }.value
                preview = data.flatMap { UIImage(data: $0) }
            case .video, .audio:
                player = AVPlayer(url: url)
            case .document:
                break
            }
        } catch {
            problem = "The file could not be fetched: \(VaultShelf.describe(error))"
        }
    }

    private func saveToPhotos(_ url: URL) async {
        notice = nil
        do {
            try await PhotoLibrary.save(url, isVideo: kind == .video)
            notice = "Saved to Photos."
        } catch {
            problem = "It was not saved to Photos: \(error.localizedDescription)"
        }
    }

    private func rename() async {
        working = true
        defer { working = false }
        do {
            try await shelf.rename(file, to: newName, in: vault)
            dismiss()
        } catch {
            problem = "It was not renamed: \(VaultShelf.describe(error))"
        }
    }

    private func delete() async {
        working = true
        defer { working = false }
        do {
            try await shelf.delete(file, in: vault)
            dismiss()
        } catch {
            problem = "It was not deleted: \(VaultShelf.describe(error))"
        }
    }
}
