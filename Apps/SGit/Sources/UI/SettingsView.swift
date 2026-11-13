import SGitVault
import SwiftUI

struct SettingsView: View {
    let shelf: VaultShelf
    @AppStorage("photos.compatible") private var compatible = false
    @State private var token = ""
    @State private var cacheBytes: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Server", value: shelf.server.host() ?? shelf.server.absoluteString)
                if shelf.hasToken {
                    LabeledContent("Access token", value: "In the Keychain")
                    Button("Remove the token", role: .destructive) { shelf.setToken("") }
                } else {
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save the token") {
                        shelf.setToken(token)
                        token = ""
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Opening and reading a vault needs only its key. Creating a vault or changing one also needs an access token, which is kept in this device's Keychain and sent only to the server above.")
            }

            Section {
                LabeledContent("Fingerprint", value: shelf.deviceFingerprint.map(VaultNaming.grouped) ?? "not made yet")
            } header: {
                Text("This device's signing key")
            } footer: {
                Text("Every commit this device makes is signed with this key. It was made on this device, is kept in its Keychain and never leaves it.")
            }

            Section {
                Toggle("Convert to JPEG and H.264 when adding", isOn: $compatible)
            } header: {
                Text("Photos and videos")
            } footer: {
                Text("Off: a photo or video goes in as it is in your library (often HEIC and HEVC), which is exact and quick, but not every browser can show it. On: the system converts it first, which takes longer and is not the original.")
            }

            Section {
                LabeledContent("On this device", value: cacheBytes.map(\.fileSizeText) ?? "…")
                Button("Empty the cache", role: .destructive) {
                    Task {
                        await shelf.emptyCache()
                        cacheBytes = shelf.cacheBytes()
                    }
                }
            } header: {
                Text("Cache")
            } footer: {
                Text("Files you have opened are kept decrypted in this app's cache folder so they open again at once. The system may empty it when space is short. Nothing in a vault is lost by emptying it.")
            }

            Section("What the vault engine has done") {
                LabeledContent("Requests", value: "\(shelf.log.totals.requests)")
                LabeledContent("Decryptions", value: "\(shelf.log.totals.decrypts)")
                LabeledContent("Checks", value: "\(shelf.log.totals.verifications)")
                LabeledContent("Errors", value: "\(shelf.log.totals.errors)")
                NavigationLink("Every step") { TrafficView(log: shelf.log) }
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionLine())
                Link("sgit.ai", destination: AppInfo.sgitSite)
                Link("Source", destination: AppInfo.source)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { cacheBytes = shelf.cacheBytes() }
    }
}

/// Every request, decryption and check the vault engine has made, newest first. No key material.
struct TrafficView: View {
    let log: VaultTrafficLog

    var body: some View {
        List(log.events.prefix(400)) { event in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.kind.rawValue).font(.caption.weight(.semibold))
                    if let status = event.status { Text("\(status)").font(.caption) }
                    Spacer()
                    if event.bytes > 0 { Text(event.bytes.fileSizeText).font(.caption) }
                    if event.durationMs >= 1 { Text("\(Int(event.durationMs)) ms").font(.caption) }
                }
                .foregroundStyle(event.kind == .error ? Color.red : Color.secondary)
                Text(event.path).font(.caption.monospaced()).lineLimit(2)
                if !event.detail.isEmpty {
                    Text(event.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Every step")
        .navigationBarTitleDisplayMode(.inline)
    }
}
