import SwiftUI

/// Language, and the tools for looking under the bonnet: diagnostics, the lane, the vault engine's log.
struct SettingsView: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.localeId") private var localeId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Language spoken") {
                        LanguageMenu()
                    }
                } footer: {
                    Text("Apple's speech model needs to know the language before it listens. The debrief is written in the same language.")
                }

                Section {
                    LabeledContent("Notes on this device", value: "\(session.store.notes.count)")
                } header: {
                    Text("Library")
                } footer: {
                    Text("Every recording is kept on this device the moment it stops, with its transcript and debrief. Saving to a vault and sending to a lane happen only when you ask.")
                }

                Section("Advanced") {
                    NavigationLink("Diagnostics and lane") { DiagnosticsView(session: session) }
                    NavigationLink("Every step the vault engine took") { TrafficView(log: book.log) }
                    NavigationLink("Lab") { LabView(store: session.store) }
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.versionLine())
                    NavigationLink("What this build does") { StatusView() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
