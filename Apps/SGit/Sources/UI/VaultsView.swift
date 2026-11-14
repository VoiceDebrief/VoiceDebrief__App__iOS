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
                                Text("\(vault.id) · \(vault.canWrite ? "read and write" : "read only") · \(vault.onDevice ? "on this device only" : "on \(shelf.serverName)")")
                                    .font(.footnote.monospaced())
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
                } label: {
                    Label("Gallery", systemImage: "square.grid.2x2")
                }
            } footer: {
                Text("Vaults to show somebody, each opened in the web Vault inside the app.")
            }
            Section {
                Button("Add a vault by its key", systemImage: "key") { adding = true }
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
        .sheet(isPresented: $adding) { AddVaultSheet(shelf: shelf) }
        .sheet(isPresented: $creating) { CreateVaultSheet(shelf: shelf) }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(shelf: shelf) }
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
                    Text("Paste the key somebody gave you, or the key sgit printed when the vault was created. A vault key can read and write. A read key can only read.")
                }
                Section {
                    TextField("Name, for this device only", text: $name)
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
    @State private var forTheTeam = true
    @State private var accessKey = ""
    @Environment(\.dismiss) private var dismiss

    private var needsKey: Bool { forTheTeam && !shelf.hasToken }
    private var ready: Bool {
        shelf.busy == nil && (!needsKey || !accessKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, for this device only", text: $name)
                } footer: {
                    Text("A new vault is a random key, an empty folder and one signed commit, made on this device. Its key is kept in this device's Keychain.")
                }
                Section {
                    Toggle("Put it on the server, to share it", isOn: $forTheTeam)
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
                         : "The vault stays on this device only: no account, no key for a server, no network. You can put it on the server later, from its Share screen.")
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
