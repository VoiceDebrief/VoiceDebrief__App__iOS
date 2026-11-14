import SwiftUI

@main
struct SGitApp: App {
    @State private var shelf = VaultShelf()
    @State private var outbox = Outbox()
    /// People, cards, inbox and keys (the shared SGitPeople package). Makes nothing at launch: it only
    /// reads the Keychain for an identity already made.
    @State private var people = PeopleModel()

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
        RootView(shelf: shelf, outbox: outbox, people: people)
            .task {
                outbox.resumeAll(shelf: shelf)
                // A vault someone sent you, sealed to your key: "Open this vault" in the inbox adds it here.
                people.openVault = { invitation in
                    let added = await shelf.add(keyText: invitation.key, name: invitation.name)
                    if added != nil { UsageLog.shared.action("vault.open-invitation") }
                    return added == nil ? (shelf.problem ?? "The vault could not be added.") : nil
                }
            }
    }
}
