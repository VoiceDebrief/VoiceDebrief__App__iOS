import SGitVault
import SwiftUI
import UIKit

/// The vaults this device knows. A vault is created and used on this device, with no server and no
/// token; a server is added, with its address and its token, when a vault should also be elsewhere.
/// Built to show how a vault works, not to hide it.
struct VaultsView: View {
    let book: VaultBook
    @State private var newName = ""
    @State private var pastedKey = ""
    @State private var pastedName = ""
    @State private var pastedFrom = ""
    @State private var serverName = ""
    @State private var serverAddress = VaultRemote.suggestedAddress
    @State private var serverToken = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                                Text(book.status(of: vault))
                                    .font(.footnote)
                                    .foregroundStyle(vault.pushProblem == nil ? Color.secondary : Color.red)
                            }
                        }
                    }
                } header: {
                    Text("Vaults")
                }

                VaultActivitySection(book: book)

                Section {
                    TextField("Name, for this device only", text: $newName)
                    Button("Create a vault") {
                        let name = newName
                        newName = ""
                        Task { await book.create(name: name) }
                    }
                    .disabled(book.busy != nil)
                } header: {
                    Text("Create")
                } footer: {
                    Text("A new vault is a random key, an empty folder and one signed commit, made and kept on this device. It needs no server, no token and no network. To have it elsewhere as well, add a server below and push the vault to it.")
                }

                Section {
                    ForEach(book.remotes) { remote in
                        NavigationLink(value: remote) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.name)
                                Text("\(remote.url.absoluteString) · \(book.hasToken(remote) ? "token in the Keychain" : "no token: read only")")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("Name", text: $serverName)
                    TextField("Address", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Access token (can be added later)", text: $serverToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add this server") {
                        if book.addRemote(name: serverName, address: serverAddress, token: serverToken) != nil {
                            serverName = ""
                            serverToken = ""
                            serverAddress = VaultRemote.suggestedAddress
                        }
                    }
                    .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Servers")
                } footer: {
                    Text("A server is somewhere a vault can be pushed to and pulled from. It stores only encrypted objects it cannot read. Its access token is needed to write to it, not to read; the token is kept in this device's Keychain and sent only to that server.")
                }

                Section {
                    SecureField("Vault key or read key", text: $pastedKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Name, for this device only", text: $pastedName)
                    if book.remotes.isEmpty {
                        Text("Add the server that holds the vault first.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Picker("From", selection: $pastedFrom) {
                            ForEach(book.remotes) { remote in
                                Text(remote.name).tag(remote.id)
                            }
                        }
                    }
                    Button("Add this vault") {
                        guard let remote = book.remote(pastedFrom) ?? book.remotes.first else { return }
                        let key = pastedKey, name = pastedName
                        pastedKey = ""
                        pastedName = ""
                        Task { await book.add(keyText: key, name: name, from: remote) }
                    }
                    .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty || book.remotes.isEmpty || book.busy != nil)
                } header: {
                    Text("Add a vault made elsewhere")
                } footer: {
                    Text("Paste the key sgit printed when the vault was created, or a read key someone gave you. The vault is read from its server; a copy can then be kept on this device.")
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
            .navigationDestination(for: VaultRemote.self) { remote in
                RemoteDetailView(book: book, remote: remote)
            }
            .onAppear {
                if book.remote(pastedFrom) == nil { pastedFrom = book.remotes.first?.id ?? "" }
            }
        }
    }
}

/// What the book is doing, what it last did, and what went wrong.
struct VaultActivitySection: View {
    let book: VaultBook

    var body: some View {
        if let busy = book.busy {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(busy)
                }
            }
        }
        if let notice = book.notice {
            Section {
                Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
            }
        }
        if let problem = book.problem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                Button("Dismiss") { book.clearProblem() }
            }
        }
    }
}

/// One server: its address and its token.
struct RemoteDetailView: View {
    let book: VaultBook
    let remote: VaultRemote
    @State private var token = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("Name", value: remote.name)
                LabeledContent("Address", value: remote.url.absoluteString)
                LabeledContent("Vaults using it", value: "\(book.vaults.filter { $0.remoteId == remote.id }.count)")
            }
            Section {
                if book.hasToken(remote) {
                    LabeledContent("Access token", value: "In the Keychain")
                    Button("Remove the token", role: .destructive) { book.setToken("", for: remote) }
                } else {
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save the token") {
                        book.setToken(token, for: remote)
                        token = ""
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Access token")
            } footer: {
                Text("Pushing a vault to \(remote.name) needs its access token. Reading needs none. The token is kept in this device's Keychain and sent only to \(remote.url.host() ?? "this server").")
            }
            VaultActivitySection(book: book)
            Section {
                Button("Remove this server", role: .destructive) {
                    book.removeRemote(remote)
                    if book.remote(remote.id) == nil {
                        CreditLedger.shared.charge(.removeServer)
                        dismiss()
                    }
                }
            } footer: {
                Text("Vaults kept on this device stay, with no server. A vault that exists only on this server must be copied to this device, or forgotten, first.")
            }
        }
        .navigationTitle(remote.name)
    }
}

/// One vault: where it lives, its head, files, history and key.
struct VaultDetailView: View {
    let book: VaultBook
    let vault: SavedVault
    @State private var contents: VaultContents?
    @State private var problem: String?
    @State private var loading = false
    @State private var showKey = false
    @State private var confirmForget = false
    @Environment(\.dismiss) private var dismiss

    /// The vault as the book holds it now: its place changes while this screen is open.
    private var now: SavedVault { book.current(vault) }

    var body: some View {
        List {
            Section {
                Text(book.status(of: vault))
                    .foregroundStyle(now.pushProblem == nil ? Color.primary : Color.red)
                if now.onDevice {
                    Picker("Server", selection: Binding(
                        get: { now.remoteId ?? "" },
                        set: { book.setRemote($0.isEmpty ? nil : $0, for: vault) })) {
                        Text("None").tag("")
                        ForEach(book.remotes) { remote in
                            Text(remote.name).tag(remote.id)
                        }
                    }
                    if let remote = book.remote(now.remoteId) {
                        if now.canWrite {
                            Button("Push to \(remote.name)") {
                                Task { await book.push(vault); await load() }
                            }
                            .disabled(book.busy != nil)
                        }
                        Button("Pull from \(remote.name)") {
                            Task { await book.pull(vault); await load() }
                        }
                        .disabled(book.busy != nil)
                    }
                } else if let remote = book.remote(now.remoteId) {
                    Button("Keep a copy on this device") {
                        Task { await book.pull(vault); await load() }
                    }
                    .disabled(book.busy != nil)
                    Text("Until then this vault is read from, and written to, \(remote.name) directly, and needs the network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Where it lives")
            } footer: {
                if now.onDevice {
                    Text("This vault is kept on this device and works with no network. Push sends what the server lacks and moves its branch forward; pull fetches what the server has. Neither overwrites: if both sides have changed, they say so and stop.")
                }
            }

            VaultActivitySection(book: book)

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
                Text("The key is the whole credential: whoever has it can open this vault, and with a vault key, write to it. There is no reset. Once the vault has been pushed to a server, sgit clone followed by this key opens the same vault on a computer.")
            }

            Section {
                Button("Forget this vault on this device", role: .destructive) { confirmForget = true }
                    .confirmationDialog("Forget this vault?", isPresented: $confirmForget, titleVisibility: .visible) {
                        Button(now.onDevice ? "Forget it and delete this device's copy" : "Forget it", role: .destructive) {
                            book.remove(vault)
                            CreditLedger.shared.charge(.removeVault)
                            dismiss()
                        }
                    } message: {
                        Text(Self.forgetWarning(now, server: book.remote(now.remoteId)?.name))
                    }
            } footer: {
                Text(Self.forgetWarning(now, server: book.remote(now.remoteId)?.name))
            }
        }
        .navigationTitle(vault.name)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard book.vaults.contains(where: { $0.id == vault.id }) else { return }
        loading = true
        defer { loading = false }
        do {
            contents = try await book.contents(of: vault)
            problem = nil
        } catch {
            problem = VaultBook.describe(error)
        }
    }

    /// What forgetting costs, which depends on where the vault is.
    static func forgetWarning(_ vault: SavedVault, server: String?) -> String {
        if !vault.onDevice {
            return "The vault stays on \(server ?? "its server"). Without its key nobody can open it again, so copy the key first if you want to keep it."
        }
        if vault.remoteId == nil || vault.remoteHead == nil {
            return "This vault exists only on this device: forgetting it deletes it, and it cannot be brought back."
        }
        if vault.remoteHead != vault.localHead {
            return "This device's copy is deleted. What has not been pushed to \(server ?? "the server") is lost. Copy the key first if you want to open the pushed part again."
        }
        return "This device's copy is deleted. The vault stays on \(server ?? "the server"); copy the key first if you want to open it again."
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
                CreditLedger.shared.charge(.readVaultFile)
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
    let note: Note
    let audioURL: URL?
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
                        Label("Save this note to the vault", systemImage: "lock.doc")
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
            Text("Save to vault")
        } footer: {
            Text("The note is already kept on this device. Saving also writes it, encrypted, into your vault as one signed commit. A vault on this device needs no network; pushing it to a server is done on the Vaults tab.")
        }
        .onAppear {
            if !writable.contains(where: { $0.id == chosen }) { chosen = writable.first?.id ?? "" }
        }
    }

    private func save() async {
        guard let vault = writable.first(where: { $0.id == chosen }) ?? writable.first else { return }
        saving = true
        result = nil
        problem = nil
        defer { saving = false }
        do {
            result = try await book.save(run: note.run, audioURL: audioURL, to: vault)
        } catch {
            problem = VaultBook.describe(error)
        }
    }
}
