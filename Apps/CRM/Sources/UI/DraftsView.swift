import MessageUI
import SwiftUI
import UIKit

/// Drafts: read, change, and send yourself from Mail or Messages. The app never sends.
struct DraftsView: View {
    let crm: CRMVault
    @State private var editing: Draft?

    private func name(_ ids: [String]) -> String {
        ids.map { id in crm.people.first { $0.id == id }?.name.value ?? "someone" }.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if crm.drafts.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "square.and.pencil",
                                       description: Text("Open a follow-up and choose Draft a message. Agents' drafts will arrive here too, each with who wrote it."))
            } else {
                List {
                    ForEach([Draft.Status.draft, .ready, .sent, .dropped], id: \.self) { status in
                        let items = crm.drafts.filter { $0.status == status }.sorted { $0.changed.at > $1.changed.at }
                        if !items.isEmpty {
                            Section(status.rawValue.capitalized) {
                                ForEach(items) { d in
                                    Button { editing = d } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("To \(name(d.to))").font(.headline)
                                            Text(d.subject ?? d.body).lineLimit(2)
                                            Text("\(d.channel.rawValue) · by \(d.created.by.name)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Drafts")
        .sheet(item: $editing) { d in
            NavigationStack { DraftEditor(crm: crm, draft: d) }
        }
    }
}

struct DraftEditor: View {
    let crm: CRMVault
    @State var draft: Draft
    @State private var composing = false
    @State private var problem: String?
    @AppStorage("crm.myName") private var myName = ""
    @Environment(\.dismiss) private var dismiss

    private var canCompose: Bool {
        draft.channel == .email ? MFMailComposeViewController.canSendMail() : MFMessageComposeViewController.canSendText()
    }

    var body: some View {
        Form {
            Section {
                if draft.channel == .email {
                    TextField("Subject", text: Binding(get: { draft.subject ?? "" }, set: { draft.subject = $0 }))
                }
                TextEditor(text: $draft.body).frame(minHeight: 180)
            } header: {
                Text("To \(DraftLog.recipients(draft, people: crm.people).joined(separator: ", "))")
            } footer: {
                Text("Written by \(draft.created.by.name). \(draft.source.saidBy), \(draft.source.from).")
            }
            if draft.status != .sent {
                Section {
                    Button(draft.channel == .email ? "Send yourself, from Mail" : "Send yourself, from Messages") { composing = true }
                        .disabled(!canCompose || DraftLog.recipients(draft, people: crm.people).isEmpty)
                    Button("Keep the draft") { Task { await keep(draft) } }
                    Button("Drop it", role: .destructive) {
                        var dropped = draft
                        dropped.status = .dropped
                        Task { await keep(dropped) }
                    }
                } footer: {
                    Text(canCompose ? "The system's sheet opens with the draft in it. Nothing is sent unless you press Send there; then it is logged here." : "This device cannot send \(draft.channel == .email ? "email (no Mail account)" : "messages").")
                }
            } else if let interaction = draft.sentAs {
                Section { Text("Sent, logged as interaction \(interaction).").font(.footnote) }
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle") }
        }
        .navigationTitle(draft.channel == .email ? "Email" : "Message")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(isPresented: $composing) {
            ComposeSheet(draft: draft, recipients: DraftLog.recipients(draft, people: crm.people)) { sent in
                composing = false
                guard sent else { return }
                Task { await logSent() }
            }
            .ignoresSafeArea()
        }
    }

    private func keep(_ d: Draft) async {
        var next = d
        next.changed = Stamp(at: max(Date().toTheSecond, d.created.at), by: crm.actor(name: myName))
        do {
            try await crm.commit(records: [.draft(next)], message: "Draft: \(next.status.rawValue)")
            dismiss()
        } catch { problem = error.localizedDescription }
    }

    private func logSent() async {
        do {
            let (done, interaction) = try DraftLog.sent(draft, by: crm.actor(name: myName), at: Date())
            try await crm.commit(records: [.draft(done), .interaction(interaction)], message: "Sent by a person: \(interaction.summary)")
            draft = done
        } catch { problem = error.localizedDescription }
    }
}

/// The system's own Mail or Messages sheet, filled with the draft. The person presses Send, or does not.
struct ComposeSheet: UIViewControllerRepresentable {
    let draft: Draft
    let recipients: [String]
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIViewController {
        switch draft.channel {
        case .email:
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = context.coordinator
            mail.setToRecipients(recipients)
            mail.setSubject(draft.subject ?? "")
            mail.setMessageBody(draft.body, isHTML: false)
            return mail
        case .message:
            let message = MFMessageComposeViewController()
            message.messageComposeDelegate = context.coordinator
            message.recipients = recipients
            message.body = draft.body
            return message
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate, MFMessageComposeViewControllerDelegate {
        let finished: (Bool) -> Void
        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result == .sent)
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            finished(result == .sent)
        }
    }
}
