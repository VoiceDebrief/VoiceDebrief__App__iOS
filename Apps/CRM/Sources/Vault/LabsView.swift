import SGitPeople
import SwiftUI
import UIKit

/// Vault apps: the explorer layer. Add a vault by its key or QR code, open its own app inside the CRM,
/// share it as a QR code, and choose for each section whether it runs natively or in a vault app.
struct LabsView: View {
    let apps: VaultApps
    @State private var keyText = ""
    @State private var name = ""
    @State private var scanning = false
    @State private var problem: String?
    @State private var adding = false
    @State private var opened: VaultApp?
    @State private var sharing: VaultApp?

    var body: some View {
        List {
            Section {
                Text("A vault can carry its own app. Open one here to try a feature before it is built into SGit CRM, or to use one that lives outside it: changing it needs no app build. When a feature is ready, it moves into the app, and the switch below chooses which one you use.")
                    .font(.footnote)
            }
            Section("Vault apps") {
                if apps.apps.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(apps.apps) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text("\(app.id) · \(app.canWrite ? "can change it" : "read only")").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("QR", systemImage: "qrcode") { sharing = app }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        Button("Open") { opened = app }.buttonStyle(.borderless)
                    }
                    .swipeActions { Button("Remove", role: .destructive) { apps.remove(app) } }
                }
            }
            Section {
                TextField("Vault key or read key", text: $keyText, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(.body.monospaced())
                TextField("Name (optional)", text: $name)
                HStack {
                    Button("Paste", systemImage: "doc.on.clipboard") { if let t = UIPasteboard.general.string { keyText = t } }
                    if QRScanner.canScan {
                        Spacer()
                        Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                    Spacer()
                    Button("Add") {
                        adding = true
                        Task {
                            do { try await apps.add(keyText: keyText, name: name); keyText = ""; name = ""; problem = nil }
                            catch { problem = error.localizedDescription }
                            adding = false
                        }
                    }
                    .disabled(keyText.isEmpty || adding)
                }
                .buttonStyle(.borderless)
                if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote) }
            } header: {
                Text("Add a vault")
            }
            Section {
                ForEach(FeatureSwitches.switchable) { section in
                    Picker(section.title, selection: Binding(get: { apps.app(for: section)?.id ?? "" },
                                                             set: { id in apps.set(section, to: apps.apps.first { $0.id == id }) })) {
                        Text("SGit CRM (native)").tag("")
                        ForEach(apps.apps) { Text($0.name).tag($0.id) }
                    }
                }
            } header: {
                Text("Where each section runs")
            } footer: {
                Text("Native is the app's own screen. A vault app runs that section from the vault instead, so it can change without a new build.")
            }
        }
        .navigationTitle("Vault apps")
        .sheet(isPresented: $scanning) {
            QRScanner { text in keyText = text; scanning = false }.ignoresSafeArea()
        }
        .fullScreenCover(item: $opened) { app in
            VaultAppScreen(app: app, keyText: apps.keyText(for: app) ?? "")
        }
        .sheet(item: $sharing) { app in
            NavigationStack { VaultQRView(app: app, apps: apps) }
        }
    }
}

enum FeatureSwitches {
    /// The sections that can be run from a vault app instead of natively.
    static let switchable: [CRMSection] = [.followUps, .people, .organisations, .introductions, .drafts, .importing]
}

/// A vault's own app, full screen inside the CRM, with its files a tap away.
struct VaultAppScreen: View {
    let app: VaultApp
    let keyText: String
    @State private var model = WebVaultModel()
    @State private var surface: WebVault.Surface = .app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WebVaultPage(keyText: keyText, path: "", surface: surface, noApp: {
                    model = WebVaultModel()
                    surface = .files
                }, accessKey: nil, model: model)
                .id(surface)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                switch model.standing {
                case .loading, .waitingForKey:
                    VStack(spacing: 12) { ProgressView(); Text("Opening \(app.name)").font(.callout) }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.triangle").padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding()
                case .open:
                    EmptyView()
                }
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: Binding(get: { surface }, set: { model = WebVaultModel(); surface = $0 })) {
                        Text("App").tag(WebVault.Surface.app)
                        Text("Files").tag(WebVault.Surface.files)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 200)
                }
            }
        }
    }
}

/// A section run from a vault app, in place of its native screen.
struct VaultAppSection: View {
    let section: CRMSection
    let app: VaultApp
    let keyText: String
    @State private var model = WebVaultModel()

    var body: some View {
        WebVaultPage(keyText: keyText, path: "", surface: .app, noApp: {}, accessKey: nil, model: model)
            .overlay(alignment: .bottom) {
                Text("\(section.title) is running from the vault app \(app.name). Switch it back in Vault apps.")
                    .font(.caption2).padding(6).background(.thinMaterial, in: Capsule()).padding(.bottom, 8)
            }
    }
}

/// A vault as a QR code to scan: its read key, unless the person asks for the full key.
struct VaultQRView: View {
    let app: VaultApp
    let apps: VaultApps
    @State private var full = false
    @State private var text: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if let text, let image = PeopleQR.image(text) {
                Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 320)
            } else {
                ProgressView()
            }
            Text(full ? "The full key: whoever scans it can change this vault." : "The read key: whoever scans it can open this vault, not change it.")
                .font(.footnote).multilineTextAlignment(.center)
            if app.canWrite {
                Toggle("Share the full key", isOn: $full).padding(.horizontal)
            }
        }
        .padding()
        .navigationTitle(app.name)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: full) { text = await apps.shareText(for: app, full: full) }
    }
}
