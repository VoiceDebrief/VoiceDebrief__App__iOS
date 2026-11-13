import SwiftUI

@main
struct SGitApp: App {
    @State private var shelf = VaultShelf()
    @State private var outbox = Outbox()

    var body: some Scene {
        WindowGroup {
            RootView(shelf: shelf, outbox: outbox)
                .task { outbox.resumeAll(shelf: shelf) }
        }
    }
}
