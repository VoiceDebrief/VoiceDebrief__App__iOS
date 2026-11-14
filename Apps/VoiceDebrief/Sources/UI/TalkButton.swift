import SwiftUI

/// Talk to Claude, from anywhere in the app: tap, speak, tap, and it goes to Claude (developer), the
/// agent working on the app (the owner, 14 November 2026: "click on it, start talking, click on it, it
/// sends"). Saying "send this now", or pressing play/pause on headphones, also finishes it.
struct TalkButton: View {
    let session: DebriefSession
    var book: VaultBook? = nil
    @AppStorage("vd.localeId") private var localeId = ""
    @AppStorage("vd.talking") private var talking = false
    @State private var showingMessages = false
    @State private var said: String?

    private var recordingHere: Bool { talking && session.recordingNote != nil }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let said {
                Text(said)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
            }
            Button {
                Task { await tap() }
            } label: {
                Image(systemName: recordingHere ? "paperplane.fill" : "waveform.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(recordingHere ? Color.red : Color.accentColor, in: Circle())
                    .shadow(radius: 4, y: 2)
                    .symbolEffect(.pulse, isActive: recordingHere)
            }
            .buttonStyle(.plain)
            .disabled(localeId.isEmpty || (session.recordingNote != nil && !talking) || RecipientStore.shared.builtIn == nil)
            .accessibilityLabel(recordingHere ? "Send to Claude" : "Talk to Claude")
            .contextMenu {
                Button("Messages to Claude", systemImage: "bubble.left.and.bubble.right") { showingMessages = true }
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 90)
        .onChange(of: session.finishRequests) { _, _ in
            if recordingHere { Task { await tap() } }
        }
        .sheet(isPresented: $showingMessages) {
            NavigationStack { MessagesToClaudeView(session: session, book: book) }
        }
    }

    private func tap() async {
        guard let claude = RecipientStore.shared.builtIn else { return }
        if recordingHere {
            talking = false
            UsageLog.shared.action("talk.send")
            if let id = await session.stopRecording() {
                session.send(noteId: id, to: claude)
                show("Sent to Claude when it is written up. Hold the button to see your messages.")
            }
        } else {
            talking = true
            UsageLog.shared.action("talk.start")
            await session.startRecording(localeId: localeId)
            if session.recordingNote == nil { talking = false }
            show("Listening. Tap again, or say \"send this now\".")
        }
    }

    private func show(_ text: String) {
        withAnimation { said = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if said == text { said = nil } }
        }
    }
}

/// Every note sent to Claude, newest first, with where it stands. Replies arrive here once the app has
/// an inbox of its own (the people session's work); until then Claude answers in the developer's chat.
struct MessagesToClaudeView: View {
    let session: DebriefSession
    var book: VaultBook? = nil
    @Environment(\.dismiss) private var dismiss
    private var desk: AgentsDesk { AgentsDesk.shared }

    private var notes: [Note] {
        session.store.notes.filter { note in
            (note.sends ?? []).contains { $0.to == RecipientStore.builtInName } || note.pendingSend?.name == RecipientStore.builtInName
        }
    }

    /// Claude's answers, written into the vault you gave it on the Agents screen: those that answer a note
    /// (by its id), and those that answer nothing in particular.
    private var replies: [AgentsReport.Message] { (desk.report?.messages ?? []).filter { $0.from != "you" } }
    private func replies(to note: Note) -> [AgentsReport.Message] {
        replies.filter { $0.replyTo == note.id }.sorted { $0.at < $1.at }
    }
    private var general: [AgentsReport.Message] {
        let noteIds = Set(notes.map(\.id))
        return replies.filter { $0.replyTo == nil || !noteIds.contains($0.replyTo!) }.sorted { $0.at > $1.at }
    }

    var body: some View {
        List {
            if !general.isEmpty {
                Section("From Claude") {
                    ForEach(general.prefix(10)) { reply($0) }
                }
            }
            Section("Your messages") {
                if notes.isEmpty {
                    Text("Nothing sent to Claude yet. Tap the button and speak.").foregroundStyle(.secondary)
                }
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).lineLimit(2)
                        Text(state(note)).font(.caption).foregroundStyle(.secondary)
                        ForEach(replies(to: note)) { reply($0) }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
            } footer: {
                Text(desk.vaultId.isEmpty
                     ? "To see Claude's replies here, give it a vault on the Agents screen: it writes its answers into that vault, encrypted, and only your devices can read them."
                     : "Replies come from your agents vault, refreshed when you open this or pull down.")
            }
        }
        .navigationTitle("Messages to Claude")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .refreshable { if let book { await desk.refresh(book: book) } }
        .task { if let book { await desk.refresh(book: book) } }
    }

    private func reply(_ message: AgentsReport.Message) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.text).font(.callout)
            Text("Claude, " + message.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func state(_ note: Note) -> String {
        if note.sendProblem != nil { return "Not sent: open the note to try again" }
        if note.pendingSend != nil { return "Waiting to send" }
        if let sent = note.sends?.last(where: { $0.to == RecipientStore.builtInName }) {
            return "Sent " + sent.at.formatted(date: .abbreviated, time: .shortened)
        }
        return ""
    }
}
