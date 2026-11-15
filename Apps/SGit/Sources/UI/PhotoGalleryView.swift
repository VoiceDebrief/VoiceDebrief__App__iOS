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

/// One picture at a time, full screen; swipe for the next. A photo is fetched at full size when shown; a
/// video plays when asked.
private struct PictureViewer: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let pictures: [VaultFile]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    init(shelf: VaultShelf, vault: SavedVault, pictures: [VaultFile], start: Int) {
        self.shelf = shelf
        self.vault = vault
        self.pictures = pictures
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                Spacer()
                Text("\(index + 1) of \(pictures.count)").font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
            }
            .padding()
        }
    }
}

private struct PicturePage: View {
    let shelf: VaultShelf
    let vault: SavedVault
    let file: VaultFile
    let isShown: Bool
    @State private var full: UIImage?
    @State private var small: UIImage?
    @State private var player: AVPlayer?
    @State private var fetching = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let image = full ?? small {
                Image(uiImage: image).resizable().scaledToFit()
            }
            if VaultListing.kind(of: file.path) == .video, player == nil {
                Button {
                    Task { await play() }
                } label: {
                    Image(systemName: fetching ? "hourglass" : "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white)
                }
            }
            VStack {
                Spacer()
                Text(VaultListing.name(of: file.path)).font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 24)
            }
        }
        .task(id: isShown) {
            if small == nil { small = await shelf.thumbnail(for: file, in: vault) }
            guard isShown, full == nil, VaultListing.kind(of: file.path) == .image else { return }
            guard let url = try? await shelf.localFile(for: file, in: vault) else { return }
            let data = await Task.detached(priority: .userInitiated) { Thumbnail.jpeg(of: url, maxPixel: 2_400) }.value
            full = data.flatMap(UIImage.init(data:))
        }
        .onChange(of: isShown) { _, shown in if !shown { player?.pause() } }
    }

    private func play() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        guard let url = try? await shelf.localFile(for: file, in: vault) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let made = AVPlayer(url: url)
        player = made
        made.play()
        UsageLog.shared.action("gallery.play")
    }
}
