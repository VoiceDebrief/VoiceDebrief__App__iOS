import AVKit
import SGitVault
import SwiftUI

/// "Show as a gallery": every photo and video in a vault, newest folder structure flattened, as a full-screen
/// grid of the small pictures kept in the vault, and a viewer that swipes from one to the next. Built for the
/// team's shared photo vaults (the owner, 15 November 2026).
struct PhotoGalleryView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    @State private var opened: OpenedPicture?
    @Environment(\.dismiss) private var dismiss

    struct OpenedPicture: Identifiable {
        let id = UUID()
        let index: Int
    }

    static func pictures(in files: [VaultFile]) -> [VaultFile] {
        VaultListing.visible(files)
            .filter { [.image, .video].contains(VaultListing.kind(of: $0.path)) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// A vault is mostly pictures when at least four of its files and at least six in ten are photos or videos.
    static func isMostlyPictures(_ files: [VaultFile]) -> Bool {
        let shown = VaultListing.visible(files)
        let pictures = Self.pictures(in: files).count
        return pictures >= 4 && pictures * 10 >= shown.count * 6
    }

    var body: some View {
        let pictures = Self.pictures(in: shelf.contents[vault.id]?.files ?? [])
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 220), spacing: 2)], spacing: 2) {
                    ForEach(Array(pictures.enumerated()), id: \.element.path) { index, file in
                        Button { opened = OpenedPicture(index: index) } label: {
                            GalleryCell(shelf: shelf, vault: vault, file: file)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .navigationTitle("\(vault.name) · \(pictures.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $opened) { opened in
                PictureViewer(shelf: shelf, vault: vault, pictures: pictures, start: opened.index)
            }
        }
    }
}

/// A square of the grid: the small picture kept in the vault, and a play mark on a video.
private struct GalleryCell: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: FileRow.icon(for: file.path)).font(.title).foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if VaultListing.kind(of: file.path) == .video {
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6)
                        .shadow(radius: 2)
                }
            }
            .background(.quaternary)
            .clipped()
            .task(id: file.blobId) { image = await shelf.thumbnail(for: file, in: vault) }
    }
}

/// Which pictures a viewer opens on, and at which one.
struct ViewerStart: Identifiable {
    let id = UUID()
    let pictures: [VaultFile]
    let index: Int
}

/// One picture at a time, full screen; swipe for the next. A photo is shown at once from the small picture
/// kept in the vault, then at full size when it has been fetched; a video plays when asked, or at once when it
/// is small or already on this device. The (i) shows the file's page: its details, Share, Save to Photos.
struct PictureViewer: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let pictures: [VaultFile]
    @State var index: Int
    @State private var info: VaultFile?
    @Environment(\.dismiss) private var dismiss

    /// The files this viewer shows: photos and videos.
    static func shows(_ path: String) -> Bool {
        [.image, .video].contains(VaultListing.kind(of: path))
    }

    /// Photos up to this size beside the one shown are fetched ahead, so that the next swipe is sharp at once.
    /// Videos are never fetched ahead.
    static let prefetchLimit = 15_000_000

    /// The photos to fetch ahead when the one at `index` is shown: the one before and the one after.
    static func neighbours(of index: Int, in pictures: [VaultFile]) -> [VaultFile] {
        [index - 1, index + 1].filter { pictures.indices.contains($0) }.map { pictures[$0] }
            .filter { VaultListing.kind(of: $0.path) == .image && $0.size <= prefetchLimit }
    }

    init(shelf: VaultShelf, vault: SavedVault, pictures: [VaultFile], start: Int) {
        self.shelf = shelf
        self.vault = vault
        self.pictures = pictures
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(pictures.enumerated()), id: \.element.path) { position, file in
                    PicturePage(shelf: shelf, vault: vault, file: file, isShown: position == index)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(index + 1) of \(pictures.count)").font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button {
                    if pictures.indices.contains(index) { info = pictures[index] }
                } label: {
                    Image(systemName: "info").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Details, share and save")
                .keyboardShortcut("i", modifiers: .command)
            }
            .padding()
            // On a Mac or an iPad with a keyboard: the arrows move from one picture to the next.
            HStack {
                Button("Previous") { if index > 0 { index -= 1 } }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next") { if index < pictures.count - 1 { index += 1 } }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .task(id: index) {
            // A short pause first, so that swiping quickly past does not fetch everything on the way.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            for file in Self.neighbours(of: index, in: pictures) where !shelf.isCached(file, in: vault) {
                _ = try? await shelf.localFile(for: file, in: vault)
            }
        }
        .sheet(item: $info) { file in
            NavigationStack {
                FileView(shelf: shelf, vault: vault, file: file)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { info = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct PicturePage: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile
    let isShown: Bool
    @State private var full: UIImage?
    @State private var small: UIImage?
    @State private var player: AVPlayer?
    @State private var fetching = false
    @State private var problem: String?

    private var isVideo: Bool { VaultListing.kind(of: file.path) == .video }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let image = full ?? small {
                Image(uiImage: image).resizable().scaledToFit()
                    .transition(.opacity)
                    .id(full == nil ? "small" : "full")
            } else {
                Image(systemName: FileRow.icon(for: file.path)).font(.system(size: 56)).foregroundStyle(.white.opacity(0.4))
            }
            if isVideo, player == nil {
                Button {
                    UsageLog.shared.action("viewer.play")
                    Task { await play() }
                } label: {
                    VStack(spacing: 10) {
                        if fetching {
                            let got = shelf.fetchedBytes[file.blobId] ?? 0
                            ProgressView(value: min(1, Double(got) / Double(max(file.size, 1))))
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                                .tint(.white)
                            Text("Fetching and decrypting · \(got.fileSizeText) of \(file.size.fileSizeText)")
                        } else {
                            Image(systemName: "play.circle.fill").font(.system(size: 64))
                            Text(shelf.isCached(file, in: vault) ? "Play" : "Play · \(file.size.fileSizeText)")
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(fetching)
            } else if !isVideo, full == nil, small != nil, let got = shelf.fetchedBytes[file.blobId], file.size > 5_000_000 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView(value: min(1, Double(got) / Double(max(file.size, 1))))
                            .progressViewStyle(.circular).tint(.white).padding(24)
                    }
                }
            }
            VStack {
                Spacer()
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.white).padding(8)
                        .background(.red.opacity(0.7), in: Capsule())
                }
                Text(VaultListing.name(of: file.path)).font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: full == nil)
        .task(id: isShown) {
            if small == nil { small = await shelf.thumbnail(for: file, in: vault) }
            guard isShown else { return }
            if isVideo {
                // A small video, or one already here, is made ready without being asked; it starts when tapped.
                if player == nil, shelf.isCached(file, in: vault) || file.size <= FileView.fetchUnasked {
                    await prepare(start: false)
                }
                return
            }
            guard full == nil else { return }
            do {
                let url = try await shelf.localFile(for: file, in: vault)
                let data = await Task.detached(priority: .userInitiated) { Thumbnail.jpeg(of: url, maxPixel: 2_400) }.value
                full = data.flatMap(UIImage.init(data:))
            } catch {
                problem = "Not fetched: \(VaultShelf.describe(error))"
            }
        }
        .onChange(of: isShown) { _, shown in if !shown { player?.pause() } }
        .onDisappear { player?.pause() }
    }

    private func play() async {
        await prepare(start: true)
    }

    private func prepare(start: Bool) async {
        if let player {
            if start { player.play() }
            return
        }
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        do {
            let url = try await shelf.localFile(for: file, in: vault)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let made = AVPlayer(url: url)
            player = made
            problem = nil
            if start && isShown { made.play() }
        } catch {
            problem = "Not fetched: \(VaultShelf.describe(error))"
        }
    }
}
