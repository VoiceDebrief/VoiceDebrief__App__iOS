import SwiftUI

@main
struct SGitApp: App {
    @State private var shelf = VaultShelf()
    @State private var outbox = Outbox()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let screen = LaunchOptions.screen {
                ScreenshotRoot(screen: screen)
            } else {
                main
            }
            #else
            main
            #endif
        }
    }

    @Environment(\.scenePhase) private var phase

    private var main: some View {
        RootView(shelf: shelf, outbox: outbox)
            .task {
                shelf.publishForSharing()
                outbox.resumeAll(shelf: shelf)
            }
            // What was shared to the app from Photos or Files while it was closed or in the background.
            .onChange(of: phase, initial: true) { _, now in
                if now == .active { outbox.takeShared(from: shelf.sharedInbox, shelf: shelf) }
            }
    }
}
