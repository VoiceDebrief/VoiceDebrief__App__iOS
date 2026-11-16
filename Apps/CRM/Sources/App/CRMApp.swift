import SwiftUI

/// SGit CRM: contacts, follow-ups and introductions, kept in an sgit vault the user owns.
/// The first use is following up the contacts and actions from Web Summit 2026.
@main
struct CRMApp: App {
    @State private var crm = CRMVault()
    @State private var apps = VaultApps()
    @State private var problem: String?

    var body: some Scene {
        WindowGroup {
            RootView(crm: crm, apps: apps, problem: problem)
                .task {
                    do { try await crm.open() } catch { problem = error.localizedDescription }
                }
        }
    }
}
