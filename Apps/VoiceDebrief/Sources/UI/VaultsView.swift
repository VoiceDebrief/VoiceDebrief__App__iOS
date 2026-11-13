import SGitVault
import SwiftUI
import UIKit

/// The vaults this device knows: add an access token, create a vault, add one made elsewhere, and
/// look inside. Built to show how a vault works, not to hide it.
struct VaultsView: View {
    let book: VaultBook
    @State private var token = ""
    @State private var newName = ""
    @State private var pastedKey = ""
    @State private var pastedName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if book.hasToken {
                        LabeledContent("Access token", value: "In the Keychain")
                        Button("Remove the token", role: .destructive) { book.setToken("") }
                    } else {
                        SecureField("SG/Send access token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save the token") {
                            book.setToken(token)
                            token = ""
                        }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Access token")
                } footer: {
                    Text("Creating a vault or writing to one needs an SG/Send access token. Opening and reading need none. The token is kept in this device's Keychain and sent only to \(book.server.host() ?? "the vault server").")
                }

                Section("Vaults on this device") {
                    if book.vaults.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    }
                    ForEach(book.vaults) { vault in
                        NavigationLink(value: vault) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vault.name)
                                Text("\(vault.id) · \(vault.canWrite ? "read and write" : "read only")")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let busy = book.busy {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(busy)
                        }
                    }
                }
                if let problem = book.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                        Button("Dismiss") { book.clearProblem() }
                    }
                }

                Section {
                    TextField("Name, for this device only", text: $newName)
                    Button("Create a vault") {
                        let name = newName
                        newName = ""
                        Task { await book.create(name: name) }
                    }
                    .disabled(!book.hasToken || book.busy != nil)
                } header: {
                    Text("Create")
                } footer: {
                    Text("A new vault is a random key, an empty folder and one signed commit. The key is made on this device and never sent: the server stores only encrypted objects it cannot read.")
                }

                Section {
                    SecureField("Vault key or read key", text: $pastedKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Name, for this device only", text: $pastedName)
                    Button("Add this vault") {
                        let key = pastedKey, name = pastedName
                        pastedKey = ""
                        pastedName = ""
                        Task { await book.add(keyText: key, name: name) }
                    }
                    .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty || book.busy != nil)
                } header: {
                    Text("Add a vault made elsewhere")
                } footer: {
                    Text("Paste the key sgit printed when the vault was created, or a read key someone gave you.")
                }

                Section("What the vault engine has done") {
                    LabeledContent("Requests", value: "\(book.log.totals.requests)")
                    LabeledContent("Downloaded", value: book.log.totals.bytesDownloaded.vaultByteString)
                    LabeledContent("From the cache", value: "\(book.log.totals.cacheHits) objects")
                    LabeledContent("Decryptions", value: "\(book.log.totals.decrypts)")
                    LabeledContent("Signature checks", value: "\(book.log.totals.verifications)")
                    LabeledContent("Key derivations", value: "\(book.log.totals.keyDerivations)")
                    NavigationLink("Every step") { TrafficView(log: book.log) }
                }
            }
            .navigationTitle("Vaults")
            .navigationDestination(for: SavedVault.self) { vault in
                VaultDetailView(book: book, vault: vault)
            }
        }
    }
}

/// One vault: its head, files, history and keys.
struct VaultDetailView: View {
    let book: VaultBook
    let vault: SavedVault
    @State private var contents: VaultContents?
    @State private var problem: String?
    @State private var loading = false
    @State private var showKey = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
            }
            if let contents {
                Section("Head") {
                    LabeledContent("Message", value: contents.head.message)
                    LabeledContent("When", value: contents.head.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Commit", value: String(contents.head.commitId.suffix(12)))
                    LabeledContent("Signature", value: Self.signature(contents.head.signature))
                    LabeledContent("Branches", value: contents.branches.map(\.name).joined(separator: ", "))
                }
                Section("Files (\(contents.files.count))") {
                    if contents.files.isEmpty {
                        Text("Empty.").foregroundStyle(.secondary)
                    }
                    ForEach(contents.files) { file in
                        NavigationLink {
                            VaultFileView(book: book, vault: vault, file: file)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path).font(.callout.monospaced())
                                Text("\(file.size.vaultByteString) · \(file.contentType ?? "unknown type")")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("History (\(contents.history.count))") {
                    ForEach(contents.history) { commit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message)
                            Text("\(commit.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(String(commit.commitId.suffix(12))) · \(Self.signature(commit.signature))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Opening the vault")
                    }
                }
            }

            Section {
                LabeledContent("Vault id", value: vault.id)
                LabeledContent("Server", value: book.server.host() ?? "")
                LabeledContent("Access", value: vault.canWrite ? "Read and write" : "Read only")
                if showKey {
                    Text(vault.keyText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("Copy the key") { UIPasteboard.general.string = vault.keyText }
                    Button("Hide the key") { showKey = false }
                } else {
                    Button("Show the key") { showKey = true }
                }
            } header: {
                Text("Key")
            } footer: {
                Text("The key is the whole credential: whoever has it can open this vault, and with a vault key, write to it. There is no reset. On a computer, sgit clone followed by this key opens the same vault.")
            }

            Section {
                Button("Forget this vault on this device", role: .destructive) {
                    book.remove(vault)
                    dismiss()
                }
            } footer: {
                Text("The vault stays on the server. Without its key nobody can open it again, so copy the key first if you want to keep it.")
            }
        }
        .navigationTitle(vault.name)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            contents = try await book.contents(of: vault)
            problem = nil
        } catch {
            problem = VaultBook.describe(error)
        }
    }

    static func signature(_ status: VaultSignatureStatus) -> String {
        switch status {
        case .verified: return "signature verified"
        case .unsigned: return "not signed"
        case .invalid: return "SIGNATURE INVALID"
        case .keyMissing: return "signer's key missing"
        case .legacy: return "signed, old form"
        }
    }
}

/// One file, fetched and decrypted when it is opened.
struct VaultFileView: View {
    let book: VaultBook
    let vault: SavedVault
    let file: VaultFile
    @State private var text: String?
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let text {
                    Text(text)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let note {
                    Text(note).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle(file.path.split(separator: "/").last.map(String.init) ?? file.path)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let data = try await book.data(of: file.path, in: vault)
                if let decoded = String(data: data, encoding: .utf8) {
                    text = decoded
                } else {
                    note = "Not text: \(data.count.vaultByteString), fetched and decrypted."
                }
            } catch {
                note = VaultBook.describe(error)
            }
        }
    }
}

/// Every request, cache hit, decryption, signature check and key derivation, newest first.
struct TrafficView: View {
    let log: VaultTrafficLog

    var body: some View {
        List {
            if log.events.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            ForEach(log.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(event.kind.rawValue).font(.footnote.weight(.semibold))
                        Spacer()
                        Text("\(event.bytes.vaultByteString) · \(Int(event.durationMs.rounded())) ms")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(event.path).font(.footnote.monospaced())
                    if !event.detail.isEmpty {
                        Text(event.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Every step")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Clear") { log.clear() }
        }
    }
}

/// After a run: save this debrief into one of the vaults, as one signed commit.
struct SaveToVaultSection: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.saveVault") private var chosen = ""
    @State private var saving = false
    @State private var result: String?
    @State private var problem: String?

    private var writable: [SavedVault] { book.vaults.filter(\.canWrite) }

    var body: some View {
        Section {
            if writable.isEmpty {
                Text("No vault to save into. Create one on the Vaults tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Vault", selection: $chosen) {
                    ForEach(writable) { vault in
                        Text(vault.name).tag(vault.id)
                    }
                }
                if saving {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Encrypting and saving")
                    }
                } else {
                    Button {
                        Task { await save() }
                    } label: {
                        Label("Save this debrief to the vault", systemImage: "lock.doc")
                    }
                }
                if let result {
                    Label(result, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Keep it")
        } footer: {
            Text("The debrief, the transcript, the run and the audio are encrypted on this device and written to your vault as one signed commit. The server stores what it cannot read.")
        }
        .onAppear {
            if !writable.contains(where: { $0.id == chosen }) { chosen = writable.first?.id ?? "" }
        }
    }

    private func save() async {
        guard let run = session.run, let vault = writable.first(where: { $0.id == chosen }) ?? writable.first else { return }
        saving = true
        result = nil
        problem = nil
        defer { saving = false }
        do {
            result = try await book.save(run: run, audioURL: session.lastAudioURL, to: vault)
        } catch {
            problem = VaultBook.describe(error)
        }
    }
}
