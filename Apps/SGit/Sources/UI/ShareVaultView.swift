import SGitVault
import SwiftUI

/// Giving somebody the vault: its key as text and as a QR code, a link for the web Vault UI, and a
/// read key for somebody who should only look. What each gives is said before it is shown.
struct ShareVaultView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    /// Files are still on their way into this vault.
    var pending = false
    @State private var token = ""
    @State private var showingKey: Bool
    @State private var showingReadKey = false
    @State private var readKey: String?
    @State private var copied: String?
    @Environment(\.dismiss) private var dismiss

    init(shelf: VaultShelf, vault: SavedVault, pending: Bool = false, showingKey: Bool = false) {
        self.shelf = shelf
        self.vault = vault
        self.pending = pending
        _showingKey = State(initialValue: showingKey)
    }

    var body: some View {
        List {
            if shelf.current(vault).onDevice {
                Section {
                    Text("This vault is on this device only. Before anybody else can open it, it has to be on a server they can reach. Sending it uploads every file, encrypted; the server cannot read them. From then on this device reads and writes the vault there.")
                        .font(.callout)
                    if !shelf.hasToken {
                        Text("\(shelf.serverName) takes new vaults only from people it knows: that is what an access key is for. It is kept in this device's Keychain and sent only to that server.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        SecureField("Access key", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save the access key") {
                            shelf.setToken(token)
                            token = ""
                        }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if pending {
                        Label("Files are still on their way into this vault. Send it when they are in.", systemImage: "clock")
                            .font(.callout)
                    }
                    if let busy = shelf.busy {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(busy)
                        }
                    }
                    if let problem = shelf.problem { ProblemLabel(text: problem) }
                    Button("Send the vault to \(shelf.serverName)", systemImage: "arrow.up.circle") {
                        Task { await shelf.sendToServer(vault, pending: pending) }
                    }
                    .disabled(!shelf.hasToken || pending || shelf.busy != nil)
                } header: {
                    Text("First, put it on a server")
                }
            }
            if !shelf.current(vault).onDevice {
                Section {
                    ShareLink(item: VaultNaming.invitation(name: vault.name, keyText: vault.keyText, readOnly: !vault.canWrite,
                                                           server: shelf.serverName)) {
                        Label(vault.canWrite ? "Send the way in" : "Send the way in, to look only", systemImage: "paperplane")
                    }
                } footer: {
                    Text("Sends a message with the key, a link for a browser and the steps for the person receiving it. Send it only to the person, by a channel you trust: it is the key itself.")
                }
            }
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("On a computer, for every file as it was added and the whole history:")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(VaultNaming.cloneCommand(keyText: "<the vault key>"))
                                .font(.footnote.monospaced())
                            Button("Copy the line with the key in it", systemImage: "doc.on.doc") {
                                Clipboard.copySecret(VaultNaming.cloneCommand(keyText: vault.keyText))
                                copied = "command"
                            }
                            .font(.footnote)
                            if copied == "command" {
                                Text("Copied. It holds the key: paste it only into your own terminal.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
