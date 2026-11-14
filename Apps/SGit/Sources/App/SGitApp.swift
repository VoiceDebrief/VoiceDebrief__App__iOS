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

    private var main: some View {
        RootView(shelf: shelf, outbox: outbox)
            .task { outbox.resumeAll(shelf: shelf) }
    }
}
