import SwiftUI

/// Language, and the tools for looking under the bonnet: diagnostics, the lane, the vault engine's log.
struct SettingsView: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.localeId") private var localeId = ""
    @AppStorage(AutoSave.switchKey) private var autoSave = true
    @AppStorage(AutoSave.vaultKey) private var saveVault = ""

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
                    Toggle("Save each finished note to a vault", isOn: $autoSave)
                    if autoSave {
                        let writable = book.vaults.filter(\.canWrite)
                        if writable.isEmpty {
                            Text("There is no vault to save into yet. Create one on the Vaults tab.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Vault", selection: $saveVault) {
                                Text("The first one").tag("")
                                ForEach(writable) { vault in
                                    Text(vault.name).tag(vault.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Every recording is kept on this device as you speak, with its transcript and debrief. With the switch on, a finished note is also written, encrypted, into the vault as one signed commit. Sending to a recipient happens only when you ask. A note that was interrupted is saved once it has been run again.")
                }

                Section {
                    NavigationLink("Identity") { IdentityView(vaults: book) }
                } footer: {
                    Text("Your key pair, this device's key, and what links them.")
                }

                Section {
                    NavigationLink {
                        CreditView()
                    } label: {
                        LabeledContent("Credit", value: Credit.money(CreditLedger.shared.balance))
                    }
                } footer: {
                    Text("Counts down as the app is used and may go below zero. In this test build a top-up is simulated: no money is taken.")
                }

                Section {
                    NavigationLink("Recipients") { RecipientsView() }
                } footer: {
                    Text("People, devices and agent sessions a note can be sent to. Add one by scanning its QR code.")
                }

                Section {
                    NavigationLink("Your words") { GlossaryView() }
                } header: {
                    Text("Experiments")
                } footer: {
                    Text("Words and names you use, for the clean text a note can be rewritten into.")
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
            .readableWidth()
            .navigationTitle("Settings")
        }
    }
}
