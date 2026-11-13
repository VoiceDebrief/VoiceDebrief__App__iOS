import PhotosUI
import SGitVault
import SwiftUI
import UniformTypeIdentifiers

/// One folder of a vault: what is on its way in, the folders, then the files.
struct VaultView: View {
    let shelf: VaultShelf
    let outbox: Outbox
    let vault: SavedVault
    let folder: String

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

    private var contents: VaultContents? { shelf.contents[vault.id] }
    private var listing: VaultListing { VaultListing.of(contents?.files ?? [], in: folder) }
    private var jobs: [UploadJob] { outbox.jobs(for: vault) }
    private var title: String { folder.isEmpty ? vault.name : VaultListing.name(of: folder) }

    var body: some View {
        let listing = self.listing
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let problem { ProblemLabel(text: problem).padding(.horizontal) }
                if let intake {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(intake)
                    }
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
                        Text(folder.isEmpty ? "This vault is empty" : "This folder is empty").font(.headline)
                        Text(vault.canWrite
                             ? "Add photos, videos or any files. A folder exists once it holds a file."
                             : "Nothing has been added here yet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                ForEach(listing.folders) { entry in
                    NavigationLink(value: FolderRoute(vault: vault, folder: entry.path)) {
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
                    }
                }
                if asList {
                    ForEach(listing.files) { file in
                        NavigationLink(value: FileRoute(vault: vault, file: file)) {
                            FileRow(shelf: shelf, vault: vault, file: file)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                        ForEach(listing.files) { file in
                            NavigationLink(value: FileRoute(vault: vault, file: file)) {
                                FileTile(shelf: shelf, vault: vault, file: file)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                if let contents, folder.isEmpty {
                    Text(Self.summary(contents))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(.vertical, 8)
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
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Share the vault", systemImage: "person.badge.key") { sharing = true }
                    Button("History", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
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
                opened = FolderRoute(vault: vault, folder: folder.isEmpty ? name : folder + "/" + name)
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
        .sheet(isPresented: $sharing) {
            NavigationStack { ShareVaultView(shelf: shelf, vault: vault) }
        }
    }

    static func summary(_ contents: VaultContents) -> String {
        let count = contents.files.count
        let bytes = contents.files.reduce(0) { $0 + $1.size }
        let when = contents.head.timestamp.formatted(date: .abbreviated, time: .shortened)
        return "\(count) file\(count == 1 ? "" : "s") · \(bytes.fileSizeText) · last change \(when)"
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
            let copied = await Task.detached { try? PickedFile.keep(scoped: url) }.value
            if let copied {
                incoming.append(IncomingFile(url: copied.url, name: url.lastPathComponent))
            } else {
                missed += 1
            }
        }
        intake = nil
        hand(incoming, missed: missed)
    }

    private func hand(_ incoming: [IncomingFile], missed: Int) {
        problem = missed == 0 ? nil : "\(missed) item\(missed == 1 ? "" : "s") could not be copied from the picker and \(missed == 1 ? "was" : "were") left out."
        guard !incoming.isEmpty else { return }
        do {
            try outbox.add(incoming, to: vault, folder: folder, existing: takenPaths, shelf: shelf)
        } catch {
            problem = "The files could not be copied into the app: \(error.localizedDescription)"
        }
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
        case .uploading: return "uploading \(Int(state.fraction * 100))%"
        case .uploaded: return "uploaded"
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
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: FileRow.icon(for: file.path)).font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
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
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: Self.icon(for: file.path)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
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
