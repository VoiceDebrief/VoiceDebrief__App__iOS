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
                                Text("\(vault.id) · \(vault.canWrite ? "read and write" : "read only")")
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
                    }
                }
            }
            Section {
                Button("Add a vault by its key", systemImage: "key") { adding = true }
                Button("Create a vault", systemImage: "plus.square") { creating = true }
            } footer: {
                if !shelf.hasToken {
                    Text("Opening and reading a vault needs nothing but its key. Creating one, or adding files, also needs an access token for the server: add it in Settings.")
                }
            }
        }
        .navigationTitle("sgit")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, for this device only", text: $name)
                } footer: {
                    Text("A new vault is a random key, an empty folder and one signed commit. The key is made on this device and is kept in its Keychain, on this device only: if the device is lost and the key was not written down or given to somebody, the vault cannot be opened again.")
                }
                if !shelf.hasToken {
                    Section {
                        Label("Creating a vault needs an access token for the server. Add one in Settings first.", systemImage: "info.circle")
                            .font(.callout)
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
                            if await shelf.create(name: name) != nil { dismiss() }
                        }
                    }
                    .disabled(!shelf.hasToken || shelf.busy != nil)
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
