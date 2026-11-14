import SGitVault
import SwiftUI
import VisionKit

/// The vaults this device knows.
struct VaultsView: View {
    let shelf: VaultShelf
    let outbox: Outbox
    @State private var adding = false
    @State private var creating = false
    @State private var showSettings = false
    @State private var forgetting: SavedVault?

    var body: some View {
        List {
            if shelf.vaults.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No vaults yet").font(.headline)
                        Text("A vault is a folder of files with a history, encrypted on this device before anything leaves it. Whoever holds its key can open it; the server that stores it cannot.")
                            .foregroundStyle(.secondary)
                        Text("Add a vault somebody gave you by its key, or create one.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let busy = shelf.busy {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(busy)
                    }
                }
            }
            if let problem = shelf.problem {
                Section {
                    ProblemLabel(text: problem)
                    Button("Dismiss") { shelf.clearProblem() }
                }
            }
            if !shelf.vaults.isEmpty {
                Section("Vaults on this device") {
                    ForEach(shelf.vaults) { vault in
                        NavigationLink(value: FolderRoute(vault: vault, folder: "")) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vault.name)
                                Text(VaultNaming.standing(canWrite: vault.canWrite, onDevice: vault.onDevice))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                let waiting = outbox.jobs(for: vault)
                                if !waiting.isEmpty {
                                    let files = waiting.reduce(0) { $0 + $1.items.count }
                                    Label("\(files) file\(files == 1 ? "" : "s") on the way in", systemImage: "arrow.up.circle")
                                        .font(.footnote)
                                        .foregroundStyle(waiting.contains { $0.problem != nil } ? Color.red : Color.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Forget", role: .destructive) { forgetting = vault }
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    GalleryView(shelf: shelf)
                        .tracked("gallery")
                } label: {
                    Label("Gallery", systemImage: "square.grid.2x2")
                }
            } footer: {
                Text("Vaults to show somebody, each opened in the web Vault inside the app.")
            }
            Section {
                Button("Add a vault you were sent", systemImage: "key") { adding = true }
                Button("Create a vault", systemImage: "plus.square") { creating = true }
            } footer: {
                Text("A vault you create is kept on this device and needs no account, no access key and no network. It goes to a server when you choose to share it.")
            }
        }
        .navigationTitle("sgit")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
        }
        .confirmationDialog(forgetting.map { "Forget \($0.name)?" } ?? "", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button(forgetting?.onDevice == true ? "Delete the vault" : "Forget the vault", role: .destructive) {
                if let vault = forgetting {
                    for job in outbox.jobs(for: vault) { outbox.discard(job.id) }
                    shelf.remove(vault)
                }
                forgetting = nil
            }
        } message: {
            if forgetting?.onDevice == true {
                Text("This vault exists only on this device. Forgetting it deletes it and everything in it, and it cannot be brought back.")
            } else {
                Text("The vault stays on the server. This device forgets its key: to open it again you will need the key from somewhere else.")
            }
        }
        .sheet(isPresented: $adding) { AddVaultSheet(shelf: shelf).tracked("add") }
        .sheet(isPresented: $creating) { CreateVaultSheet(shelf: shelf).tracked("create") }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(shelf: shelf) }
                .tracked("settings")
        }
    }
}

struct AddVaultSheet: View {
    let shelf: VaultShelf
    @State private var key = ""
    @State private var name = ""
    @State private var scanning = false
    @Environment(\.dismiss) private var dismiss

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Vault key, read key or vault link", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if canScan {
                        Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                } footer: {
                    Text("Paste what you were sent: a vault key (you can add and change), a read key (you can only look) or a link to the vault. To add files to a shared vault you also need an access key for \(shelf.serverName), which is not part of the vault key: ask whoever sent it, and enter it in Settings.")
                }
                Section {
                    TextField("Your name for it", text: $name)
                }
                if let busy = shelf.busy {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(busy)
                        }
                    }
                }
                if let problem = shelf.problem {
                    Section { ProblemLabel(text: problem) }
                }
            }
            .navigationTitle("Add a vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await shelf.add(keyText: key, name: name) != nil { dismiss() }
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || shelf.busy != nil)
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScanner { text in
                        key = VaultNaming.keyText(from: text)
                        scanning = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan a vault key")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } }
                    }
                }
            }
            .onAppear { shelf.clearProblem() }
        }
    }
}

struct CreateVaultSheet: View {
    let shelf: VaultShelf
    @State private var name = ""
    @State private var forTheTeam: Bool
    @State private var accessKey = ""

    init(shelf: VaultShelf) {
        self.shelf = shelf
        // On for somebody who already has an access key; off, and nothing asked for, for somebody who has not.
        _forTheTeam = State(initialValue: shelf.hasToken)
    }

    @Environment(\.dismiss) private var dismiss

    private var needsKey: Bool { forTheTeam && !shelf.hasToken }
    private var ready: Bool {
        shelf.busy == nil && (!needsKey || !accessKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text("The name is for you, on this device: anybody you share the vault with names it themselves. The vault's key is made here and kept on this device only, so if this device is lost and the key was never given to anybody or written down, the vault cannot be opened again.")
                }
                Section {
                    Toggle("Share it: put it on the server", isOn: $forTheTeam)
                    if needsKey {
                        SecureField("Access key for \(shelf.serverName)", text: $accessKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if forTheTeam {
                        LabeledContent("Access key", value: "In the Keychain")
                    }
                } footer: {
                    Text(forTheTeam
                         ? "The vault is made here, then sent to \(shelf.serverName), encrypted, so that anybody you give its key to can open it. The server takes new vaults only from people it knows: that is what the access key is for. It is kept in this device's Keychain."
                         : "The vault stays on this device only: no account, no access key, no network, and nobody else can open it. You can put it on the server later, from its Share screen, which is when an access key is needed.")
                }
                if let busy = shelf.busy {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(busy)
                        }
                    }
                }
                if let problem = shelf.problem {
                    Section { ProblemLabel(text: problem) }
                }
            }
            .navigationTitle("Create a vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if needsKey { shelf.setToken(accessKey) }
                            guard let made = await shelf.create(name: name) else { return }
                            // If sending fails the vault is still made, on this device, and the list says why.
                            if forTheTeam { await shelf.sendToServer(made) }
                            dismiss()
                        }
                    }
                    .disabled(!ready)
                }
            }
            .onAppear { shelf.clearProblem() }
        }
    }
}

/// The camera, looking for one QR code.
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                    done = true
                    found(text)
                    return
                }
            }
        }
    }
}
