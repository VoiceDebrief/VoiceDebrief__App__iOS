import CoreImage
import PhotosUI
import SGitPeople
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The people layer's one entry: You, Contacts, Inbox. Placed on the root list by the sgit app. The secrets that
/// belong to the identity (access keys, keys received from people) are `KeysAndAccessView`, which the sgit app's
/// Secrets screen shows; its own entries live in vaults.
struct PeopleHome: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let hub = model.hub {
                List {
                    Section {
                        NavigationLink { YouView(model: model, hub: hub) } label: {
                            Label("You", systemImage: "person.crop.square")
                        }
                        NavigationLink { ContactsView(hub: hub) } label: {
                            Label("Contacts (\(hub.contacts.count))", systemImage: "person.2")
                        }
                        NavigationLink { InboxView(hub: hub) } label: {
                            Label(hub.unread > 0 ? "Inbox, \(hub.unread) new" : "Inbox", systemImage: "tray")
                        }
                    }
                    if hub.inbox == nil {
                        Section {
                            Text("You have no inbox yet, so nobody can write to you. An inbox needs the server's access key: ask someone who has it to invite you, from the You screen.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear { hub.note(.opened) }
                .onChange(of: scenePhase) { _, phase in
                    hub.note(phase == .active ? .foreground : .background)
                }
            } else {
                MakeKeysView(model: model)
            }
        }
        .navigationTitle("People")
    }
}

/// Before there are keys: what will be made, and where it is kept.
struct MakeKeysView: View {
    @Bindable var model: PeopleModel
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                Text("To exchange cards, messages and secrets with people, this app makes a key pair for you: one key to receive (RSA 4096) and one to sign (P-256). The private halves stay in your iCloud Keychain, so your other devices are the same you; Apple cannot read them. Nothing is sent anywhere until you send it.")
                    .font(.callout)
            }
            Section("Your name, as others will see it") {
                TextField("Name", text: $name)
                    .textContentType(.name)
            }
            Section {
                Button {
                    Task { await model.makeIdentity(name: name) }
                } label: {
                    if model.making { ProgressView() } else { Text("Make my keys") }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.making)
            }
            if let problem = model.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
        }
    }
}

// MARK: You

struct YouView: View {
    @Bindable var model: PeopleModel
    let hub: PeopleHub
    @State private var showInvitation = false
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Your card") {
                if let text = hub.myCardText {
                    PeopleQRImage(text: text)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Your contact card as a QR code")
                    if let link = hub.myCardLink {
                        ShareLink(item: link) { Label("Send your card", systemImage: "square.and.arrow.up") }
                    }
                    Text(hub.inbox == nil ? "Your card has no inbox yet: people can seal things to you but not drop them in an inbox."
                                          : "Your card carries your inbox: anyone with it can write to you; only your key opens what they write.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Your keys") {
                LabeledContent("Encryption key", value: hub.identity.bundle.fingerprint)
                LabeledContent("Signing key", value: hub.identity.bundle.signingFingerprint)
                Text("Made on this device and kept in iCloud Keychain (\(PeopleModel.peopleService)). Compare these with someone face to face to check it is really you.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Inbox") {
                if let inbox = hub.inbox {
                    LabeledContent("Vault", value: inbox.address.vault)
                    LabeledContent("Server", value: inbox.address.server)
                    if let last = hub.lastCheck { LabeledContent("Last checked", value: last.formatted(date: .omitted, time: .shortened)) }
                } else if hub.hasAccessKey {
                    Button("Make my inbox") {
                        working = true
                        Task {
                            do { try await hub.makeInbox(signer: model.commitSigner()); message = "Your inbox is ready." }
                            catch { message = error.localizedDescription }
                            working = false
                        }
                    }
                    .disabled(working)
                } else {
                    Button("I have an invitation") { showInvitation = true }
                    Text("Someone with the server's access key seals it to your card and sends it back as a code or a link. Opening it keeps the key, makes your inbox and sends them your full card.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("You")
        .sheet(isPresented: $showInvitation) {
            CodeInputSheet(title: "Open an invitation", prompt: "Scan, choose a picture of, or paste the code or link you were sent.") { text in
                do {
                    try await hub.accept(invitation: text, signer: model.commitSigner(), met: .byMessage)
                    message = "Invitation accepted: the access key is kept, your inbox is made and your card was sent."
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
    }
}

// MARK: Contacts

struct ContactsView: View {
    let hub: PeopleHub
    @State private var adding = false

    var body: some View {
        List {
            if hub.contacts.isEmpty {
                Text("No contacts yet. Add someone by scanning their card, choosing a picture of it, or pasting the link they sent.")
                    .foregroundStyle(.secondary)
            }
            ForEach(hub.contacts) { contact in
                NavigationLink { ContactDetailView(hub: hub, contactId: contact.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                        Text(contact.canReceive ? contact.met.words : "\(contact.met.words). No inbox yet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in offsets.map { hub.contacts[$0].id }.forEach(hub.removeContact) }
        }
        .navigationTitle("Contacts")
        .toolbar { Button { adding = true } label: { Label("Add", systemImage: "plus") } }
        .sheet(isPresented: $adding) {
            CodeInputSheet(title: "Add a contact", prompt: "Scan their card, choose a picture of it, or paste the link they sent.") { text in
                do {
                    try hub.addContact(from: text, met: CodeInputSheet.lastWasCamera ? .inPerson : .byMessage)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
    }
}

struct ContactDetailView: View {
    let hub: PeopleHub
    let contactId: String
    @State private var text = ""
    @State private var status: String?
    @State private var invitation: String?
    @State private var sending = false

    var contact: Contact? { hub.contact(contactId) }

    var body: some View {
        Form {
            if let contact {
                Section {
                    LabeledContent("Name on their card", value: contact.card.name)
                    LabeledContent("How you met", value: contact.met.words)
                    LabeledContent("Encryption key", value: contact.card.fingerprint)
                    LabeledContent("Signing key", value: contact.card.signingFingerprint)
                    if let verified = contact.verifiedAt {
                        LabeledContent("Checked face to face", value: verified.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Button("We compared these keys face to face") { hub.markVerified(contact.id) }
                    }
                }
                if contact.canReceive {
                    Section("Write to \(contact.name)") {
                        TextField("Message", text: $text, axis: .vertical)
                        Button("Send") { send { try await hub.sendText(text, to: contact); text = "" } }
                            .disabled(text.isEmpty || sending)
                        Button(contact.sentMyCardAt == nil ? "Send them your card" : "Send your card again") {
                            send { try await hub.sendMyCard(to: contact) }
                        }
                        .disabled(sending)
                    }
                } else {
                    Section("No inbox yet") {
                        Text("\(contact.name) has no inbox. If they are new, give them the server's access key: it is sealed to their card, and only their key opens it.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Invite: seal the access key to them") {
                            do { invitation = try hub.invite(newcomerCard: try contact.card.text(), inPerson: false, met: contact.met) }
                            catch { status = error.localizedDescription }
                        }
                    }
                }
                if let invitation {
                    Section("The invitation") {
                        if invitation.utf8.count <= SealedText.maxQRCharacters { PeopleQRImage(text: invitation).frame(maxWidth: .infinity) }
                        ShareLink(item: SealedText.link(invitation)) { Label("Send the invitation", systemImage: "square.and.arrow.up") }
                        Text("Sealed to \(contact.name)'s key: safe to send by WhatsApp or email. It expires in 7 days.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let status { Section { Text(status).font(.footnote) } }
            }
        }
        .navigationTitle(contact?.name ?? "Contact")
    }

    private func send(_ action: @escaping () async throws -> Void) {
        sending = true
        Task {
            do { try await action(); status = "Sent." } catch { status = error.localizedDescription }
            sending = false
        }
    }
}

// MARK: Inbox

struct InboxView: View {
    let hub: PeopleHub

    var body: some View {
        List {
            if hub.inbox == nil {
                Text("You have no inbox yet.").foregroundStyle(.secondary)
            } else if hub.messages.isEmpty {
                Text("Nothing has arrived.").foregroundStyle(.secondary)
            }
            if let problem = hub.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            ForEach(hub.messages) { received in
                NavigationLink { MessageView(hub: hub, received: received) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if received.readAt == nil { Circle().fill(.tint).frame(width: 8, height: 8).accessibilityLabel("New") }
                            Text(hub.senderName(received)).font(.headline)
                        }
                        Text(received.message?.text ?? "Could not be opened").lineLimit(2)
                        Text(received.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .refreshable { await hub.checkNow() }
        .toolbar {
            Button { Task { await hub.checkNow() } } label: { Label("Check now", systemImage: "arrow.clockwise") }
                .disabled(hub.checking || hub.inbox == nil)
        }
    }
}

struct MessageView: View {
    let hub: PeopleHub
    let received: ReceivedMessage
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("From", value: hub.senderName(received))
                LabeledContent("Checked", value: trustWords)
                LabeledContent("Arrived", value: received.receivedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let message = received.message {
                Section { Text(message.text) }
                if let secret = message.secret {
                    Section("A secret: \(secret.kind.words)") {
                        Text(secret.name)
                        Button("Keep it in my secrets") {
                            do { _ = try hub.keepSecret(from: received); status = "Kept in your secrets." }
                            catch { status = error.localizedDescription }
                        }
                        .disabled(!(received.trust == .contact || received.trust == .cardInside))
                    }
                }
                if let vault = message.vault {
                    Section("A vault") {
                        LabeledContent("Name", value: vault.name)
                        LabeledContent("Access", value: vault.canWrite ? "Read and write" : "Read only")
                    }
                }
            } else if let problem = received.problem {
                Section { Text(problem).foregroundStyle(.secondary) }
            }
            if let status { Section { Text(status).font(.footnote) } }
        }
        .navigationTitle("Message")
        .onAppear { hub.markRead(received.id) }
    }

    var trustWords: String {
        switch received.trust {
        case .contact: "Signed by a contact"
        case .cardInside: "Signed by the card it carries (not yet a contact)"
        case .unknown: "Signed by a key you do not know"
        case .forged: "Does not check: do not trust it"
        case .unsigned: "Not signed"
        case nil: "Could not be opened"
        }
    }
}

// MARK: Keys and access

/// The secrets the identity holds (the store in iCloud Keychain): access keys, keys and passwords received from
/// people or given to them. For the sgit app's Secrets screen to place as one section or one screen.
struct KeysAndAccessView: View {
    let hub: PeopleHub
    @State private var adding = false

    var body: some View {
        List {
            if hub.secretList.isEmpty {
                Text("No keys yet. An access key arrives when someone invites you; add one yourself, or a key or token, and give it to a contact in one step.")
                    .foregroundStyle(.secondary)
            }
            ForEach(hub.secretList) { secret in
                NavigationLink { SecretDetailView(hub: hub, secretId: secret.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(secret.name.isEmpty ? secret.kind.words : secret.name)
                        Text(secret.heldBy.isEmpty ? secret.kind.words : "\(secret.kind.words), held by \(secret.heldBy.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in offsets.map { hub.secretList[$0].id }.forEach(hub.removeSecret) }
            Section {
                Toggle("Keep secrets in iCloud Keychain", isOn: Binding(get: { hub.secrets.synchronise }, set: { hub.setSynchronise($0) }))
                Text("On: your other devices have them too, end-to-end encrypted. Off: on this device only.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Keys and access")
        .toolbar { Button { adding = true } label: { Label("Add", systemImage: "plus") } }
        .sheet(isPresented: $adding) { AddSecretSheet(hub: hub) }
    }
}

struct AddSecretSheet: View {
    let hub: PeopleHub
    @Environment(\.dismiss) private var dismiss
    @State private var kind = SecretKind.password
    @State private var name = ""
    @State private var value = ""
    @State private var server = InboxAddress.defaultServer
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(SecretKind.allCases, id: \.self) { Text($0.words).tag($0) }
                }
                TextField("Name", text: $name)
                SecureField("The secret", text: $value)
                if kind == .accessKey || kind == .vaultKey { TextField("Server", text: $server).textInputAutocapitalization(.never) }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .navigationTitle("Add a secret")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do {
                            try hub.addSecret(kind: kind, name: name, value: value,
                                              server: (kind == .accessKey || kind == .vaultKey) ? server : nil)
                            dismiss()
                        } catch { problem = error.localizedDescription }
                    }
                    .disabled(value.isEmpty)
                }
            }
        }
    }
}

struct SecretDetailView: View {
    let hub: PeopleHub
    let secretId: String
    @State private var shown: String?
    @State private var status: String?
    @State private var choosing = false

    var secret: KeptSecret? { hub.secretList.first { $0.id == secretId } }

    var body: some View {
        Form {
            if let secret {
                Section {
                    LabeledContent("Kind", value: secret.kind.words)
                    if let server = secret.server { LabeledContent("Server", value: server) }
                    LabeledContent("Version", value: "\(secret.version)")
                    if let from = secret.receivedFrom { LabeledContent("From", value: "\(from.name), \(from.at.formatted(date: .abbreviated, time: .omitted))") }
                }
                Section("The secret") {
                    if let shown {
                        Text(shown).font(.body.monospaced()).textSelection(.enabled)
                        Button("Copy (cleared from the clipboard in 2 minutes)") {
                            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: shown]],
                                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        }
                        Button("Hide") { self.shown = nil }
                    } else {
                        Button("Show, with Face ID") {
                            Task {
                                if await SecretsStore.unlock(reason: "Show \(secret.name)") { shown = hub.secrets.value(secret.id) }
                                else { status = "Not shown: Face ID or the passcode is needed." }
                            }
                        }
                    }
                }
                Section("Who holds it") {
                    if secret.heldBy.isEmpty { Text("Nobody you gave it to.").foregroundStyle(.secondary) }
                    ForEach(secret.heldBy, id: \.fingerprint) { holder in
                        LabeledContent(holder.name, value: holder.version < secret.version
                                       ? "has version \(holder.version): send the new one" : "since \(holder.at.formatted(date: .abbreviated, time: .omitted))")
                    }
                    Button("Give it to a contact") { choosing = true }
                        .disabled(hub.contacts.allSatisfy { !$0.canReceive })
                }
                if let status { Section { Text(status).font(.footnote) } }
            }
        }
        .navigationTitle(secret?.name ?? "Secret")
        .confirmationDialog("Give it to", isPresented: $choosing) {
            ForEach(hub.contacts.filter(\.canReceive)) { contact in
                Button(contact.name) {
                    Task {
                        do { try await hub.shareSecret(secretId, with: contact); status = "Sealed to \(contact.name) and sent." }
                        catch { status = error.localizedDescription }
                    }
                }
            }
        }
    }
}

// MARK: Shared pieces

/// A QR code for a card or a sealed code. Never a raw key.
struct PeopleQRImage: View {
    let text: String

    var body: some View {
        if let image = PeopleQR.image(text) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 280)
        } else {
            Text("Too long for one QR code: send the link instead.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Scan, choose a picture of, or paste a code. `submit` returns nil when it worked, or why not.
struct CodeInputSheet: View {
    let title: String
    let prompt: String
    let submit: (String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var scanning = false
    @State private var picture: PhotosPickerItem?
    @State private var problem: String?
    /// Whether the last code came from the camera, which counts as meeting in person.
    @MainActor static var lastWasCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(prompt).font(.callout) }
                Section {
                    Button { scanning = true } label: { Label("Scan with the camera", systemImage: "qrcode.viewfinder") }
                    PhotosPicker(selection: $picture, matching: .images) { Label("Choose a picture of the code", systemImage: "photo") }
                }
                Section("Or paste it") {
                    TextField("Code or link", text: $pasted, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Use what I pasted") { use(pasted, camera: false) }.disabled(pasted.isEmpty)
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $scanning) {
                QRScanner { found in
                    scanning = false
                    use(found, camera: true)
                }
            }
            .onChange(of: picture) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let text = Self.qrText(in: data) { use(text, camera: false) }
                    else { problem = "No QR code was found in that picture." }
                }
            }
        }
    }

    private func use(_ text: String, camera: Bool) {
        Self.lastWasCamera = camera
        Task {
            if let why = await submit(text) { problem = why } else { dismiss() }
        }
    }

    /// The text of the first QR code in a picture.
    static func qrText(in data: Data) -> String? {
        guard let image = CIImage(data: data),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
