import SwiftUI
import UIKit

/// The inbox, live from Gmail (W5 in the app): read your mail, reply, write, and send yourself, as yourself.
/// Separate from the mailbox twin: this is the person's own view, straight from Google; the twin is the copy
/// in a vault that agents work on. Nothing is sent unless you press Send and confirm.
struct InboxView: View {
    let crm: CRMVault
    let auth: GoogleAuth
    @State private var messages: [MailMessage] = []
    @State private var loading = false
    @State private var problem: String?
    @State private var clientField = ""
    @State private var scanning = false
    @State private var composing: OutgoingMail?
    @State private var search = ""

    private var gmail: GmailClient { GmailClient(token: { [auth] in try await auth.token() }) }

    var body: some View {
        Group {
            if !auth.hasClient {
                setup
            } else if !auth.signedIn {
                connect
            } else {
                inbox
            }
        }
        .navigationTitle("Inbox")
        .sheet(isPresented: $scanning) {
            QRScanner { text in clientField = text; scanning = false }.ignoresSafeArea()
        }
        .sheet(item: Binding(get: { composing.map(ComposeItem.init) }, set: { composing = $0?.mail })) { item in
            NavigationStack {
                ComposeView(mail: item.mail, crm: crm) { mail, consent in
                    try await gmail.send(mail, consent: consent)
                    await logSent(mail)
                }
            }
        }
    }

    private var setup: some View {
        Form {
            Section {
                Text("To read and send your Gmail here, SGit CRM needs the id of an iOS OAuth client made for it in Google Cloud. It is not a secret.")
                TextField("…apps.googleusercontent.com", text: $clientField, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                HStack {
                    Button("Paste", systemImage: "doc.on.clipboard") { if let t = UIPasteboard.general.string { clientField = t } }
                    if QRScanner.canScan { Spacer(); Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true } }
                    Spacer()
                    Button("Save") { auth.setClient(clientField) }.disabled(!clientField.contains("googleusercontent"))
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Connect Gmail")
            } footer: {
                Text("In Google Cloud, in the project with the Gmail OAuth app: Clients, Create client, type iOS, bundle id ai.sgit.crm.app. Then copy its client id here, or show it as a QR code and scan it.")
            }
        }
    }

    private var connect: some View {
        Form {
            Section {
                Button(auth.signingIn ? "Signing in" : "Sign in with Google") {
                    Task {
                        do {
                            try await auth.signIn()
                            auth.setAccount(try await gmail.address())
                            await load()
                        } catch { problem = error.localizedDescription }
                    }
                }
                .disabled(auth.signingIn)
                if let problem { Text(problem).foregroundStyle(.red) }
            } footer: {
                Text("Google's own sign-in opens. SGit CRM asks to read your mail and to send as you, nothing else. The token stays in this device's Keychain; sign out revokes it.")
            }
            Section { Button("Use another client id", role: .destructive) { auth.setClient(""); clientField = "" } }
        }
    }

    private var inbox: some View {
        List {
            if let account = auth.account { Text(account).font(.caption).foregroundStyle(.secondary) }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote) }
            ForEach(messages) { m in
                NavigationLink {
                    MessageView(message: m, crm: crm) { body in
                        composing = OutgoingMail.reply(to: m, from: auth.account ?? "", body: body)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if m.unread { Circle().fill(.blue).frame(width: 7, height: 7) }
                            Text(m.from).font(.headline).lineLimit(1)
                            Spacer()
                            Text(m.date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(m.subject).font(.subheadline).lineLimit(1)
                        Text(m.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if crm.people.contains(where: { $0.emails.contains { ContactKeys.email($0.value) == m.fromAddress } }) {
                            Label("In your CRM", systemImage: "person.crop.circle.badge.checkmark").font(.caption2).foregroundStyle(.green)
                        }
                    }
                }
            }
            if messages.isEmpty && !loading { Text("Pull down to read your inbox.").foregroundStyle(.secondary) }
        }
        .searchable(text: $search)
        .onSubmit(of: .search) { Task { await load() } }
        .refreshable { await load() }
        .overlay { if loading && messages.isEmpty { ProgressView() } }
        .task { if messages.isEmpty { await load() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Write", systemImage: "square.and.pencil") {
                    composing = OutgoingMail(from: auth.account ?? "", to: [], subject: "", body: "")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Sign out of Gmail", role: .destructive) { Task { await auth.signOut(); messages = [] } }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            messages = try await gmail.list(query: search)
            problem = nil
        } catch { problem = error.localizedDescription }
    }

    /// A message sent to someone in the CRM is kept there as an interaction.
    private func logSent(_ mail: OutgoingMail) async {
        let ids = crm.people.filter { p in p.emails.contains { e in mail.to.map(ContactKeys.email).contains(ContactKeys.email(e.value)) } }.map(\.id)
        guard !ids.isEmpty else { return }
        let at = Date().toTheSecond
        let stamp = Stamp(at: at, by: crm.actor(name: auth.account ?? "Me"))
        let i = Interaction(id: RecordID.make(), created: stamp, changed: stamp,
                            source: Source(saidBy: auth.account ?? "Me", at: at, from: "Gmail, sent from SGit CRM"),
                            at: at, channel: .email, people: ids, summary: "Sent: \(mail.subject)")
        try? await crm.commit(records: [.interaction(i)], message: "Sent by a person from the inbox: \(mail.subject)")
    }
}

private struct ComposeItem: Identifiable {
    let mail: OutgoingMail
    let id = UUID()
}

struct MessageView: View {
    let message: MailMessage
    let crm: CRMVault
    let reply: (String) -> Void
    @State private var added = false

    private var inCRM: Bool { crm.people.contains { $0.emails.contains { ContactKeys.email($0.value) == message.fromAddress } } }

    var body: some View {
        List {
            Section {
                LabeledContent("From", value: "\(message.from) <\(message.fromAddress)>")
                LabeledContent("To", value: message.to)
                LabeledContent("Date", value: message.date.formatted(date: .abbreviated, time: .shortened))
            }
            Section(message.subject) {
                Text(message.body.isEmpty ? message.snippet : message.body).textSelection(.enabled)
            }
            Section {
                Button("Reply", systemImage: "arrowshape.turn.up.left") { reply("") }
                if inCRM || added {
                    Label("In your CRM", systemImage: "checkmark")
                } else {
                    Button("Add \(message.from) to the CRM", systemImage: "person.badge.plus") {
                        let at = Date().toTheSecond
                        let stamp = Stamp(at: at, by: crm.actor(name: "Me"))
                        let src = Source(saidBy: "Gmail", at: at, from: "the message \(message.id)")
                        let p = Person(id: RecordID.make(), created: stamp, changed: stamp, source: src,
                                       name: Sourced(message.from), emails: [Sourced(message.fromAddress)], tags: ["gmail"])
                        let i = Interaction(id: RecordID.make(), created: stamp, changed: stamp, source: src, at: message.date.toTheSecond,
                                            channel: .email, people: [p.id], summary: "Email: \(message.subject)")
                        Task { try? await crm.commit(records: [.person(p), .interaction(i)], message: "From Gmail: \(message.from)"); added = true }
                    }
                }
            }
        }
        .navigationTitle(message.from)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Proof that a person pressed Send and confirmed this message. Its initialiser is fileprivate, so only the
/// confirmation below can make one; Gmail's send call takes nothing else.
struct PersonConfirmedSend: Sendable {
    let raw: String
    fileprivate init(confirmed mail: OutgoingMail) { raw = mail.raw }
}

/// Writing or replying. Send asks once more, then sends as you through Gmail.
struct ComposeView: View {
    @State var mail: OutgoingMail
    let crm: CRMVault
    let send: (OutgoingMail, PersonConfirmedSend) async throws -> Void
    @State private var toText = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("To", text: $toText).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                TextField("Subject", text: $mail.subject)
            }
            Section { TextEditor(text: $mail.body).frame(minHeight: 220) }
            if let problem { Text(problem).foregroundStyle(.red) }
        }
        .navigationTitle(mail.inReplyTo == nil ? "New email" : "Reply")
        .onAppear { toText = mail.to.joined(separator: ", ") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(sending ? "Sending" : "Send") { confirming = true }
                    .disabled(sending || recipients.isEmpty)
            }
        }
        .confirmationDialog("Send this email as \(mail.from)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Send to \(recipients.joined(separator: ", "))") {
                Task {
                    sending = true
                    defer { sending = false }
                    var m = mail
                    m.to = recipients
                    do { try await send(m, PersonConfirmedSend(confirmed: m)); dismiss() } catch { problem = error.localizedDescription }
                }
            }
            Button("Not yet", role: .cancel) {}
        }
    }

    private var recipients: [String] {
        toText.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).map(String.init).filter(ContactKeys.isEmail)
    }
}
