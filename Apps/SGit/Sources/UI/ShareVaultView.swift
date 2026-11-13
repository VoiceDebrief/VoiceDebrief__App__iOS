import SGitVault
import SwiftUI

/// Giving somebody the vault: its key as text and as a QR code, a link for the web Vault UI, and a
/// read key for somebody who should only look. What each gives is said before it is shown.
struct ShareVaultView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    @State private var showingKey = false
    @State private var showingReadKey = false
    @State private var readKey: String?
    @State private var copied: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if vault.canWrite {
                Section {
                    Label {
                        Text("Whoever holds the vault key can read every file in this vault and its whole history, add files, change them and delete them. It cannot be taken back: the only way to shut somebody out is a new vault. Give it to people, not to places.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.callout)
                }
                Section("Vault key: read and write") {
                    if showingKey {
                        SecretBlock(text: vault.keyText, label: "vault key", copied: $copied)
                        if let link = VaultNaming.webLink(keyText: vault.keyText) {
                            ShareLink(item: link) { Label("Send a link that opens it in a browser", systemImage: "link") }
                        }
                    } else {
                        Button("Show the vault key", systemImage: "eye") { showingKey = true }
                    }
                }
            }
            Section {
                if showingReadKey, let readKey {
                    SecretBlock(text: readKey, label: "read key", copied: $copied)
                } else {
                    Button("Show the read key", systemImage: "eye") {
                        Task {
                            if let key = try? await shelf.key(for: vault) { readKey = key.exportReadKey() }
                            showingReadKey = true
                        }
                    }
                }
            } header: {
                Text("Read key: read only")
            } footer: {
                Text("Whoever holds the read key can read every file and the history, now and later, and can change nothing. It cannot be taken back either. This app and the sgit command open a vault from a read key; the web Vault UI does not yet.")
            }
            if let copied {
                Section {
                    Label("The \(copied) is on the clipboard for two minutes, on this device only.", systemImage: "doc.on.clipboard")
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Share \(vault.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

/// A secret as text that can be selected, a button that copies it, and its QR code.
struct SecretBlock: View {
    let text: String
    let label: String
    @Binding var copied: String?

    var body: some View {
        Text(text)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
        Button("Copy the \(label)", systemImage: "doc.on.doc") {
            Clipboard.copySecret(text)
            copied = label
        }
        if let code = QRCode.image(text) {
            Image(uiImage: code)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("QR code of the \(label)")
        }
    }
}
