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

    var body: some View {
        NavigationStack {
            VaultsView(shelf: shelf, outbox: outbox)
                .navigationDestination(for: FolderRoute.self) { route in
                    VaultView(shelf: shelf, outbox: outbox, vault: route.vault, folder: route.folder)
                }
                .navigationDestination(for: FileRoute.self) { route in
                    FileView(shelf: shelf, vault: route.vault, file: route.file)
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
