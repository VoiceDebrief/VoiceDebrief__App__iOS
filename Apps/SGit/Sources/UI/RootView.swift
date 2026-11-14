import SGitVault
import SwiftUI

/// One folder of one vault.
struct FolderRoute: Hashable {
    let vault: SavedVault
    let folder: String
}

/// One file of one vault.
struct FileRoute: Hashable {
    let vault: SavedVault
    let file: VaultFile
}

struct RootView: View {
    let shelf: VaultShelf
    let outbox: Outbox
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            VaultsView(shelf: shelf, outbox: outbox)
                .tracked("vaults")
                .navigationDestination(for: FolderRoute.self) { route in
                    VaultView(shelf: shelf, outbox: outbox, vault: route.vault, folder: route.folder)
                        .tracked(route.folder.isEmpty ? "vault" : "vault.folder")
                }
                .navigationDestination(for: FileRoute.self) { route in
                    FileView(shelf: shelf, vault: route.vault, file: route.file)
                        .tracked("file")
                }
        }
        .onChange(of: phase) { _, now in
            if now == .active { Task { await shelf.refreshFromOtherDevices() } }
        }
        // In the app switcher, and whenever the app is not in front, nothing of a vault or a secret is shown.
        .overlay {
            if phase != .active {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Label("sgit", systemImage: "lock.fill").font(.title2.weight(.semibold))
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// A problem, said plainly, with a way to dismiss it.
struct ProblemLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
    }
}
