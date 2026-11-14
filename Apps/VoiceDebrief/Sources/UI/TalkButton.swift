import SwiftUI

/// Talk to Claude, from anywhere in the app: tap, speak, tap, and it goes to Claude (developer), the
/// agent working on the app (the owner, 14 November 2026: "click on it, start talking, click on it, it
/// sends"). Saying "send this now", or pressing play/pause on headphones, also finishes it.
struct TalkButton: View {
    let session: DebriefSession
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
            NavigationStack { MessagesToClaudeView(session: session) }
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
    @Environment(\.dismiss) private var dismiss

    private var notes: [Note] {
        session.store.notes.filter { note in
            (note.sends ?? []).contains { $0.to == RecipientStore.builtInName } || note.pendingSend?.name == RecipientStore.builtInName
        }
    }

    var body: some View {
        List {
            if notes.isEmpty {
                Text("Nothing sent to Claude yet. Tap the button and speak.").foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).lineLimit(2)
                    Text(state(note)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
            } footer: {
                Text("Replies will appear here once the app has its own inbox, which is being built. Until then Claude answers in the developer's chat.")
            }
        }
        .navigationTitle("Messages to Claude")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
