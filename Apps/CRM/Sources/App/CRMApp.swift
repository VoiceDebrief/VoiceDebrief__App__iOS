import SwiftUI

/// SGit CRM: contacts, follow-ups and introductions, kept in an sgit vault the user owns.
/// The first use is following up the contacts and actions from Web Summit 2026.
@main
struct CRMApp: App {
    @State private var crm = CRMVault()
    @State private var apps = VaultApps()
    @State private var keys = KeysModel()
    @State private var google = GoogleAuth()
    @State private var problem: String?
    /// "Try with sample data": a separate vault of invented records, so the real one is never mixed with them.
    @AppStorage("crm.sample") private var sample = false
    @AppStorage("crm.myName") private var myName = ""
    @State private var sampleCRM: CRMVault?

    private var active: CRMVault { sample ? (sampleCRM ?? crm) : crm }

    var body: some Scene {
        WindowGroup {
            RootView(crm: active, apps: apps, keys: keys, google: google, problem: problem, sample: $sample)
                .id(sample && sampleCRM != nil)
                .task {
                    do { try await crm.open() } catch { problem = error.localizedDescription }
                }
                .task(id: sample) {
                    guard sample, sampleCRM == nil else { return }
                    let s = CRMVault(store: KeychainStore(service: "ai.sgit.crm.app.sample"), root: CRMVault.sampleRoot)
                    do {
                        try await s.open()
                        try await s.seedSampleIfEmpty(name: myName)
                        sampleCRM = s
                    } catch { problem = error.localizedDescription; sample = false }
                }
        }
    }
}
