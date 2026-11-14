import PhotosUI
import SGitVault
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One folder of a vault: what is on its way in, the folders, then the files.
struct VaultView: View {
    let shelf: VaultShelf
    let outbox: Outbox
    let vault: SavedVault
    /// The folder this screen was opened on.
    let folder: String
    /// On a wide screen the tree on the left chooses the folder, in place of pushing a new screen.
    @State private var chosen: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("browse.asList") private var asList = false
    @AppStorage("photos.compatible") private var compatible = false
    @State private var loading = false
    @State private var problem: String?
    @State private var intake: String?
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var sharing = false
    @State private var namingFolder = false
    @State private var newFolder = ""
    @State private var opened: FolderRoute?
    @State private var showingHistory = false
    @State private var dropping = false
    @State private var exporting: FolderExport?

    private var contents: VaultContents? { shelf.contents[vault.id] }
    private var onDevice: Bool { shelf.current(vault).onDevice }
    private var here: String { chosen ?? folder }
    private var wide: Bool { sizeClass == .regular && folder.isEmpty }
    private var listing: VaultListing { VaultListing.of(contents?.files ?? [], in: here) }
    private var jobs: [UploadJob] { outbox.jobs(for: vault) }
    private var title: String { here.isEmpty || wide ? vault.name : VaultListing.name(of: here) }

    var body: some View {
        HStack(spacing: 0) {
            if wide {
                FolderTree(name: vault.name, nodes: VaultListing.tree(paths: contents?.files.map(\.path) ?? []),
                           here: here) { chosen = $0 }
                    .frame(width: 250)
                Divider()
            }
            files
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if contents == nil { await load() } }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if vault.canWrite {
                    Menu("Add", systemImage: "plus") {
                        Button("Photos and videos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                        Button("Files", systemImage: "doc") { pickingFiles = true }
                        Button("New folder", systemImage: "folder.badge.plus") {
                            newFolder = ""
                            namingFolder = true
                        }
                    }
                }
                Button("Share", systemImage: "person.badge.plus") { sharing = true }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("History", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    let inside = VaultListing.under(contents?.files ?? [], folder: here)
                    if !inside.isEmpty {
                        Button(VaultNaming.saveOut(count: inside.count, bytes: inside.reduce(0) { $0 + $1.size }),
                               systemImage: "square.and.arrow.down.on.square") { Task { await saveOut() } }
                    }
                    Button(asList ? "Show as a grid" : "Show as a list",
                           systemImage: asList ? "square.grid.2x2" : "list.bullet") { asList.toggle() }
                }
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $picked, maxSelectionCount: nil,
                      matching: .any(of: [.images, .videos]),
                      preferredItemEncoding: compatible ? .compatible : .current)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await take(photos: items) }
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await take(files: urls) }
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .alert("New folder", isPresented: $namingFolder) {
            TextField("Name", text: $newFolder)
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                let name = VaultNaming.cleanFolder(newFolder)
                guard !name.isEmpty else { return }
                let path = here.isEmpty ? name : here + "/" + name
                if wide { chosen = path } else { opened = FolderRoute(vault: vault, folder: path) }
            }
        } message: {
            Text("The folder appears in the vault once a file has been added to it.")
        }
        .navigationDestination(item: $opened) { route in
            VaultView(shelf: shelf, outbox: outbox, vault: route.vault, folder: route.folder)
        }
        .navigationDestination(isPresented: $showingHistory) {
            HistoryView(shelf: shelf, vault: vault)
        }
        .sheet(item: $exporting) { export in
            FolderExporter(url: export.url).ignoresSafeArea()
        }
        .sheet(isPresented: $sharing) {
            NavigationStack { ShareVaultView(shelf: shelf, vault: vault, pending: !jobs.isEmpty) }
        }
    }

    /// Fetches every file in the open folder and beneath it, lays them out as they are in the vault, and
    /// hands the folder to the Files app. The files are the originals: decrypted, not converted.
    private func saveOut() async {
        let wanted = VaultListing.under(contents?.files ?? [], folder: here)
        guard !wanted.isEmpty, intake == nil else { return }
        let name = here.isEmpty ? VaultNaming.clean(vault.name) : VaultListing.name(of: here)
        let target = FileManager.default.temporaryDirectory
            .appending(path: "out-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        problem = nil
        defer { intake = nil }
        do {
            for (index, file) in wanted.enumerated() {
                intake = "Getting file \(index + 1) of \(wanted.count) ready to save"
                let local = try await shelf.localFile(for: file, in: vault)
                let place = target.appending(path: VaultListing.relative(file.path, to: here))
                try FileManager.default.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
                // A link costs no space; a copy is the fallback across volumes.
                if (try? FileManager.default.linkItem(at: local, to: place)) == nil {
                    try FileManager.default.copyItem(at: local, to: place)
                }
            }
            exporting = FolderExport(url: target)
        } catch {
            problem = "The folder could not be saved: \(error.localizedDescription)"
        }
    }

    static func summary(_ contents: VaultContents) -> String {
        let count = contents.files.count
        let bytes = contents.files.reduce(0) { $0 + $1.size }
        let when = contents.head.timestamp.formatted(date: .abbreviated, time: .shortened)
        return "\(count) file\(count == 1 ? "" : "s") · \(bytes.fileSizeText) · last change \(when)"
    }

    /// The folder that is open: what is on its way in, its folders, then its files. Files dropped on it
    /// are added to it.
    @ViewBuilder private var files: some View {
        let listing = self.listing
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if contents != nil {
                    let waiting = jobs.reduce(0) { $0 + $1.items.count }
                    Label(VaultNaming.arrival(onDevice: onDevice, server: shelf.serverName, pendingFiles: waiting,
                                              failed: jobs.contains { $0.problem != nil }, checked: shelf.checkedAt[vault.id]),
                          systemImage: waiting > 0 ? "arrow.up.circle" : (onDevice ? "iphone" : "checkmark.icloud"))
                        .font(.footnote)
                        .foregroundStyle(jobs.contains { $0.problem != nil } ? Color.red : Color.secondary)
                        .padding(.horizontal)
                }
                if wide, !here.isEmpty {
                    Text(here.replacingOccurrences(of: "/", with: " / "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                if let problem { ProblemLabel(text: problem).padding(.horizontal) }
                if let intake {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(intake)
                    }
                    .padding(.horizontal)
                }
                if onDevice, here.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("On this device only", systemImage: "iphone").font(.subheadline.weight(.semibold))
                        Text("Nobody else can open this vault yet, and it is not copied anywhere. To share it, send it to the server.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Share…") { sharing = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                ForEach(jobs) { job in
                    UploadCard(outbox: outbox, shelf: shelf, job: job)
                        .padding(.horizontal)
                }
                if contents == nil, loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Opening the vault")
                    }
                    .padding()
                }
                if contents != nil, listing.folders.isEmpty, listing.files.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(here.isEmpty ? "This vault is empty" : "This folder is empty").font(.headline)
                        Text(vault.canWrite
                             ? "Add photos, videos or any files, or drop them here. A folder exists once it holds a file."
                             : "Nothing has been added here yet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                ForEach(listing.folders) { entry in
                    if wide {
                        Button { chosen = entry.path } label: { FolderRow(entry: entry) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: FolderRoute(vault: vault, folder: entry.path)) { FolderRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
                if asList {
                    ForEach(listing.files) { file in
                        NavigationLink(value: FileRoute(vault: vault, file: file)) {
                            FileRow(shelf: shelf, vault: vault, file: file)
                                .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        .onDrag { shelf.itemProvider(for: file, in: vault) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 8)], alignment: .leading, spacing: 10) {
                        ForEach(listing.files) { file in
                            NavigationLink(value: FileRoute(vault: vault, file: file)) {
                                FileTile(shelf: shelf, vault: vault, file: file)
                            }
                            .buttonStyle(.plain)
                            .onDrag { shelf.itemProvider(for: file, in: vault) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if let contents, here.isEmpty {
                    Text(Self.summary(contents))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard vault.canWrite, !urls.isEmpty else { return false }
            Task { await take(files: urls) }
            return true
        } isTargeted: { dropping = $0 }
        .overlay {
            if dropping, vault.canWrite {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            try await shelf.load(vault)
            problem = nil
        } catch {
            problem = "The vault could not be read: \(VaultShelf.describe(error))"
        }
    }

    /// The paths taken in this vault: what it holds and what is on its way in.
    private var takenPaths: [String] {
        (contents?.files.map(\.path) ?? []) + jobs.flatMap { $0.items.map(\.path) }
    }

    private func take(photos items: [PhotosPickerItem]) async {
        var incoming: [IncomingFile] = []
        var missed = 0
        for (index, item) in items.enumerated() {
            intake = "Copying \(index + 1) of \(items.count) from Photos"
            do {
                if let file = try await item.loadTransferable(type: PickedFile.self) {
                    incoming.append(IncomingFile(url: file.url, name: file.url.lastPathComponent))
                } else {
                    missed += 1
                }
            } catch {
                missed += 1
            }
        }
        intake = nil
        hand(incoming, missed: missed)
    }

    private func take(files urls: [URL]) async {
        var incoming: [IncomingFile] = []
        var missed = 0
        for (index, url) in urls.enumerated() {
            intake = "Copying \(index + 1) of \(urls.count)"
            let copied = await Task.detached { PickedFile.keepAll(scoped: url) }.value
            if copied.isEmpty { missed += 1 } else { incoming += copied }
        }
        intake = nil
        hand(incoming, missed: missed)
    }

    private func hand(_ incoming: [IncomingFile], missed: Int) {
        problem = missed == 0 ? nil : "\(missed) item\(missed == 1 ? "" : "s") could not be copied from the picker and \(missed == 1 ? "was" : "were") left out."
        guard !incoming.isEmpty else { return }
        do {
            try outbox.add(incoming, to: vault, folder: here, existing: takenPaths, shelf: shelf)
        } catch {
            problem = "The files could not be copied into the app: \(error.localizedDescription)"
        }
    }
}

/// A folder, as a row among the files.
struct FolderRow: View {
    let entry: VaultListing.Folder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).foregroundStyle(.primary)
                Text("\(entry.files) file\(entry.files == 1 ? "" : "s") · \(entry.bytes.fileSizeText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// The folders of a vault as a tree, down the left of a wide screen, as the web Vault has it.
struct FolderTree: View {
    let name: String
    let nodes: [VaultListing.Node]
    let here: String
    let choose: (String) -> Void

    var body: some View {
        List {
            row(name: name, path: "", icon: "lock.rectangle.stack")
            OutlineGroup(nodes, children: \.children) { node in
                row(name: node.name, path: node.path, icon: "folder")
            }
        }
        .listStyle(.sidebar)
    }

    private func row(name: String, path: String, icon: String) -> some View {
        Button { choose(path) } label: {
            Label(name, systemImage: icon)
                .fontWeight(here == path ? .semibold : .regular)
                .foregroundStyle(here == path ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One selection on its way in: a bar for the whole, a line for each file, and what to do when it stops.
struct UploadCard: View {
    let outbox: Outbox
    let shelf: VaultShelf
    let job: UploadJob

    var body: some View {
        let isRunning = outbox.running.contains(job.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: job.problem == nil ? "arrow.up.circle" : "exclamationmark.triangle")
                    .foregroundStyle(job.problem == nil ? Color.accentColor : Color.red)
                Text(job.message).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                Text(job.totalBytes.fileSizeText).font(.footnote).foregroundStyle(.secondary)
            }
            ProgressView(value: outbox.fraction(of: job))
            ForEach(job.items) { item in
                let state = outbox.progress[item.id] ?? ItemProgress(phase: item.uploaded ? .uploaded : .waiting)
                HStack(spacing: 8) {
                    Text(item.name).font(.footnote).lineLimit(1)
                    Spacer()
                    Text(Self.words(state, item: item)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let problem = job.problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
                Text("Nothing was lost: the files are kept in the app until they are in the vault.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if !isRunning {
                    Button(job.problem == nil ? "Carry on" : "Try again") { outbox.start(job.id, shelf: shelf) }
                        .buttonStyle(.borderedProminent)
                }
                Button(isRunning ? "Cancel" : "Discard", role: .destructive) { outbox.discard(job.id) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    static func words(_ state: ItemProgress, item: UploadItem) -> String {
        switch state.phase {
        case .waiting: return item.sealed == nil ? "waiting" : "encrypted, waiting"
        case .encrypting: return "encrypting \(Int(state.fraction * 100))%"
        case .uploading: return "storing \(Int(state.fraction * 100))%"
        case .uploaded: return "stored"
        }
    }
}

/// A square tile: the image itself when it is one, an icon when it is not.
struct FileTile: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            // A square that takes its size from the grid, with the picture laid over it and cut to it:
            // a picture given the square's frame directly pushes the tile wider than its column.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: FileRow.icon(for: file.path)).font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(VaultListing.name(of: file.path))
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Text(file.size.fileSizeText).font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: file.blobId) {
            image = await shelf.thumbnail(for: file, in: vault)
        }
    }
}

struct FileRow: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 44, height: 44)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: Self.icon(for: file.path)).foregroundStyle(.secondary)
                    }
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(VaultListing.name(of: file.path)).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                Text(file.size.fileSizeText).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .task(id: file.blobId) {
            image = await shelf.thumbnail(for: file, in: vault)
        }
    }

    static func icon(for path: String) -> String {
        switch VaultListing.kind(of: path) {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc"
        }
    }
}

/// A folder made ready to leave the app.
struct FolderExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system's "save to Files" for a whole folder.
struct FolderExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
