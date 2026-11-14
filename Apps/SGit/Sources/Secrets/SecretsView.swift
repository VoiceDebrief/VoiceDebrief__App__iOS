import LocalAuthentication
import SGitVault
import SwiftUI

/// Face ID (or the device passcode) before a hidden value is shown or copied.
enum Unlock {
    static func ask(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Every secret this device can open, grouped by the vault that holds it.
struct SecretsView: View {
    let shelf: VaultShelf
    @State private var entries: [String: [SecretEntry]] = [:]
    @State private var loading = false
    @State private var problem: String?
    @State private var search = ""
    @State private var adding: SecretKindOfEntry?
    @State private var choosingKind = false

    var body: some View {
        List {
            if shelf.secretVaults.isEmpty, !loading {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No secrets yet", systemImage: "key.viewfinder").font(.headline)
                        Text("Passwords, device passcodes, Wi-Fi, cards, tokens and keys, each kept as one encrypted file in a vault. The first one makes a vault called My secrets on this device.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            if let problem { Section { ProblemLabel(text: problem) } }
            ForEach(shelf.secretVaults) { vault in
                let shown = filtered(entries[vault.id] ?? [])
                Section {
                    if shown.isEmpty {
                        Text(search.isEmpty ? "Nothing in it yet." : "Nothing matches.").foregroundStyle(.secondary)
                    }
                    if shelf.current(vault).onDevice, shelf.hasToken, vault.canWrite {
                        Button("Put these on the server, for your other devices", systemImage: "icloud.and.arrow.up") {
                            Task {
                                UsageLog.shared.action("secrets.send-to-server")
                                if !(await shelf.sendToServer(vault)) { problem = shelf.problem }
                                await reload()
                            }
                        }
                    }
                    ForEach(shown) { entry in
                        NavigationLink {
                            SecretView(shelf: shelf, vault: vault, entry: entry) { await reload() }
                                .tracked("secret")
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name.isEmpty ? entry.kind.words : entry.name)
                                    Text(entry.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } icon: {
                                Image(systemName: entry.kind.symbol)
                            }
                        }
                    }
                } header: {
                    Text(vault.name)
                } footer: {
                    Text(Self.standing(of: vault, in: shelf))
                }
            }
        }
        .searchable(text: $search, prompt: "Name, website or user")
        .navigationTitle("Secrets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Add a secret", systemImage: "plus") {
                    ForEach(SecretKindOfEntry.allCases) { kind in
                        Button(kind.words, systemImage: kind.symbol) { adding = kind }
                    }
                }
            }
        }
        .overlay { if loading && entries.isEmpty { ProgressView("Opening your secrets") } }
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(item: $adding) { kind in
            NavigationStack {
                SecretEditView(shelf: shelf, vault: nil, entry: .new(kind), isNew: true) { await reload() }
            }
            .tracked("secret.edit")
        }
    }

    private func filtered(_ list: [SecretEntry]) -> [SecretEntry] {
        let wanted = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return list }
        return list.filter { entry in
            entry.name.lowercased().contains(wanted) || entry.fields.contains { !$0.hidden && $0.value.lowercased().contains(wanted) }
        }
    }

    /// Where a vault of secrets stands, in a sentence.
    static func standing(of vault: SavedVault, in shelf: VaultShelf) -> String {
        if shelf.current(vault).onDevice {
            return "On this device only. Your other devices do not have these yet."
        }
        return vault.canWrite ? "On \(shelf.serverName): every device and person with this vault's key sees these."
                              : "Read only: you can see these and not change them."
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        problem = nil
        for vault in shelf.vaults {
            if shelf.contents[vault.id] == nil { _ = try? await shelf.load(vault) }
        }
        var found: [String: [SecretEntry]] = [:]
        for vault in shelf.secretVaults {
            do {
                found[vault.id] = try await shelf.secrets(in: vault)
            } catch {
                problem = "\(vault.name) could not be read: \(VaultShelf.describe(error))"
            }
        }
        entries = found
    }
}

/// One secret: its fields, hidden ones behind Face ID.
struct SecretView: View {
    let shelf: VaultShelf
    let vault: SavedVault
    @State var entry: SecretEntry
    let changed: () async -> Void
    @State private var unlocked = false
    @State private var copied: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(shelf: VaultShelf, vault: SavedVault, entry: SecretEntry, changed: @escaping () async -> Void) {
        self.shelf = shelf
        self.vault = vault
        _entry = State(initialValue: entry)
        self.changed = changed
    }

    var body: some View {
        List {
            if let problem { Section { ProblemLabel(text: problem) } }
            Section {
                ForEach(entry.fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Text(field.hidden && !unlocked ? String(repeating: "•", count: 12) : field.value)
                                .font(field.hidden ? .body.monospaced() : .body)
                                .textSelection(.disabled)
                            Spacer()
                            Button {
                                Task { await copy(field) }
                            } label: {
                                Image(systemName: copied == field.label ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy \(field.label)")
                        }
                    }
                }
                if entry.fields.contains(where: \.hidden), !unlocked {
                    Button("Show hidden values", systemImage: "faceid") { Task { await unlock() } }
                }
            } header: {
                Label(entry.kind.words, systemImage: entry.kind.symbol)
            } footer: {
                if copied != nil { Text("Copied. It stays on this device and leaves the clipboard in two minutes.") }
            }
            if !entry.note.isEmpty {
                Section("Note") { Text(entry.note) }
            }
            Section("Kept in") {
                LabeledContent("Vault", value: vault.name)
                LabeledContent("Changed", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("By", value: VaultNaming.signer(keyId: entry.changedBy, deviceKeyId: shelf.deviceKeyId))
            }
            if vault.canWrite {
                Section {
                    Button("Delete this secret", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Deleting is a commit like any other: the vault's history keeps the earlier versions, and anyone who holds this vault's key can still read them there.")
                }
            }
        }
        .navigationTitle(entry.name.isEmpty ? entry.kind.words : entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vault.canWrite {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        Task {
                            if !entry.fields.contains(where: \.hidden) || unlocked {
                                editing = true
                            } else if await unlock() {
                                editing = true
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                SecretEditView(shelf: shelf, vault: vault, entry: entry, isNew: false) {
                    await changed()
                    if let fresh = try? await shelf.secrets(in: vault).first(where: { $0.id == entry.id }) { entry = fresh }
                }
            }
            .tracked("secret.edit")
        }
        .confirmationDialog("Delete \(entry.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await shelf.delete(entry, in: vault)
                        await changed()
                        dismiss()
                    } catch {
                        problem = VaultShelf.describe(error)
                    }
                }
            }
        }
    }

    @discardableResult
    private func unlock() async -> Bool {
        let ok = await Unlock.ask("Show the hidden values of \(entry.name.isEmpty ? entry.kind.words : entry.name)")
        unlocked = ok
        if ok { UsageLog.shared.action("secret.show") }
        return ok
    }

    private func copy(_ field: SecretEntry.Field) async {
        if field.hidden, !unlocked, !(await unlock()) { return }
        Clipboard.copySecret(field.value)
        copied = field.label
        UsageLog.shared.action(field.hidden ? "secret.copy-hidden" : "secret.copy")
    }
}

/// Adding or changing one secret.
struct SecretEditView: View {
    let shelf: VaultShelf
    /// Nil for a new secret: it goes to the vault chosen here, My secrets by default.
    let vault: SavedVault?
    @State var entry: SecretEntry
    let isNew: Bool
    let saved: () async -> Void
    @State private var target: String?
    @State private var saving = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(shelf: VaultShelf, vault: SavedVault?, entry: SecretEntry, isNew: Bool, saved: @escaping () async -> Void) {
        self.shelf = shelf
        self.vault = vault
        _entry = State(initialValue: entry)
        self.isNew = isNew
        self.saved = saved
    }

    private var writable: [SavedVault] { shelf.secretVaults.filter(\.canWrite) }

    var body: some View {
        Form {
            Section {
                TextField("Name, such as Office Wi-Fi", text: $entry.name)
            }
            Section(entry.kind.words) {
                ForEach($entry.fields) { $field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label).font(.footnote).foregroundStyle(.secondary)
                        if field.hidden {
                            SecureField(field.label, text: $field.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            TextField(field.label, text: $field.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
                if entry.kind.takesGeneratedPassword, let index = entry.fields.firstIndex(where: \.hidden) {
                    Button("Make a strong password", systemImage: "wand.and.stars") {
                        entry.fields[index].value = PasswordMaker.make()
                        UsageLog.shared.action("secret.generate")
                    }
                }
            }
            Section("Note") {
                TextField("Anything else worth knowing", text: $entry.note, axis: .vertical).lineLimit(2...6)
            }
            if isNew, vault == nil, !writable.isEmpty {
                Section {
                    Picker("Keep it in", selection: Binding(get: { target ?? writable.first?.id }, set: { target = $0 })) {
                        ForEach(writable) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Everyone who holds the chosen vault's key will be able to read this secret.")
                }
            }
            if let problem { Section { ProblemLabel(text: problem) } }
        }
        .navigationTitle(isNew ? "New \(entry.kind.words.lowercased())" : "Change")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving" : "Save") { Task { await save() } }
                    .disabled(saving || entry.name.trimmingCharacters(in: .whitespaces).isEmpty || entry.filled.isEmpty)
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        problem = nil
        var place: SavedVault? = vault
        if place == nil, let target { place = writable.first(where: { $0.id == target }) }
        if place == nil { place = writable.first }
        if place == nil { place = await shelf.makeSecretsHome() }
        guard let place else {
            problem = shelf.problem ?? "No vault could be made for your secrets."
            return
        }
        do {
            try await shelf.save(entry, in: place, isNew: isNew)
            await saved()
            dismiss()
        } catch {
            problem = VaultShelf.describe(error)
        }
    }
}
