import SGitPeople
import SwiftUI
import UIKit

/// My card and the cards of people I met (W12): show mine as a QR code, scan theirs, check it is them,
/// and put their key on their record in the CRM.
struct KeysView: View {
    let keys: KeysModel
    let crm: CRMVault
    @AppStorage("crm.myName") private var myName = ""
    @State private var nameField = ""
    @State private var scanning = false
    @State private var pasted = ""
    @State private var message: String?

    var body: some View {
        Form {
            if let hub = keys.hub {
                Section {
                    if let text = hub.myCardText, let image = PeopleQR.image(text) {
                        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 280).frame(maxWidth: .infinity)
                            .accessibilityLabel("Your contact card as a QR code")
                    }
                    if let link = hub.myCardLink {
                        ShareLink(item: link) { Label("Send your card", systemImage: "square.and.arrow.up") }
                    }
                } header: {
                    Text("Your card: \(hub.name)")
                } footer: {
                    Text("Your public keys, signed together. Whoever scans it can seal things that only you can open. It holds no secret.")
                }
                Section("Your keys") {
                    LabeledContent("Encryption key", value: hub.identity.bundle.fingerprint).font(.footnote.monospaced())
                    LabeledContent("Signing key", value: hub.identity.bundle.signingFingerprint).font(.footnote.monospaced())
                }
                Section {
                    if QRScanner.canScan {
                        Button("Scan their card", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                    TextField("Or paste a card or its link", text: $pasted, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add the pasted card") { add(pasted, inPerson: false); pasted = "" }.disabled(pasted.isEmpty)
                    if let message { Text(message).font(.footnote) }
                } header: {
                    Text("Someone else's card")
                }
                Section("People whose cards you have") {
                    if hub.contacts.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                    ForEach(hub.contacts) { contact in
                        ContactKeyRow(contact: contact, hub: hub, crm: crm, actorName: myName)
                    }
                }
            } else {
                Section {
                    TextField("Your name, as others will see it", text: $nameField)
                    Button(keys.making ? "Making your keys" : "Make my keys") {
                        Task { await keys.makeIdentity(name: nameField); if keys.hasIdentity && myName.isEmpty { myName = nameField } }
                    }
                    .disabled(nameField.trimmingCharacters(in: .whitespaces).isEmpty || keys.making)
                    if let problem = keys.problem { Text(problem).foregroundStyle(.red) }
                } footer: {
                    Text("An encryption key and a signing key, made on this device and kept in iCloud Keychain. Your card shares the public halves; the private halves never leave your devices.")
                }
            }
        }
        .navigationTitle("Cards and keys")
        .onAppear { if nameField.isEmpty { nameField = myName } }
        .sheet(isPresented: $scanning) {
            QRScanner { text in scanning = false; add(text, inPerson: true) }.ignoresSafeArea()
        }
    }

    private func add(_ text: String, inPerson: Bool) {
        do {
            let contact = try keys.addCard(text, inPerson: inPerson)
            message = "Added \(contact.card.name). Compare the keys with them to check it is really them."
        } catch { message = error.localizedDescription }
    }
}

struct ContactKeyRow: View {
    let contact: Contact
    let hub: PeopleHub
    let crm: CRMVault
    let actorName: String
    @State private var problem: String?

    private var inCRM: Bool { crm.people.contains { CardLink.has($0, contact) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contact.nickname ?? contact.card.name).font(.headline)
                Spacer()
                Text(contact.verifiedAt == nil ? contact.met.words : "checked face to face").font(.caption).foregroundStyle(.secondary)
            }
            Text(contact.card.fingerprint).font(.caption2.monospaced()).foregroundStyle(.secondary)
            HStack {
                if contact.verifiedAt == nil {
                    Button("They match") { hub.markVerified(contact.id) }
                }
                Spacer()
                if inCRM {
                    Label("In the CRM", systemImage: "checkmark").font(.caption)
                } else {
                    Button("Add to the CRM") {
                        let person = CardLink.person(for: contact, existing: crm.people, by: crm.actor(name: actorName), at: Date())
                        Task {
                            do { try await crm.commit(records: [.person(person)], message: "Card of \(person.name.value)") }
                            catch { problem = error.localizedDescription }
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
    }
}
