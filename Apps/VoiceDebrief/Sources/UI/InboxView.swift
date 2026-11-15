import SwiftUI

/// The Inbox: what waits for you, and every memo you sent with what came of it, newest first (the owner,
/// 15 November 2026: "how do I follow up this memo? I need to see the flow, and receive your follow-ups in a
/// much more interactive way; what decisions do I need to provide, what is next"). It reads the report the
/// conductor writes into your agents vault, and your own notes; nothing here is made up by the app.
struct InboxView: View {
    let session: DebriefSession
    let book: VaultBook
    var go: (RootTab) -> Void = { _ in }
    private var desk: AgentsDesk { AgentsDesk.shared }

    private var replies: [AgentsReport.Message] { (desk.report?.messages ?? []).filter { $0.from != "you" } }
    private var decisions: [AgentsReport.Decision] { desk.report?.decisions ?? [] }
    private var nextSteps: [String] { desk.report?.nextSteps ?? [] }

    /// Your notes that went to someone, newest first.
    private var sentNotes: [Note] {
        session.store.notes.filter { !($0.sends ?? []).isEmpty || $0.pendingSend != nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if desk.vaultId.isEmpty {
                Section {
                    Label("Give Claude a vault on the Agents screen: its answers, decisions and next steps arrive here, encrypted, readable only on your devices.",
                          systemImage: "lock.shield")
                    Button("Open Agents") { go(.agents) }
                }
            }
            if !decisions.isEmpty {
                Section("Decisions for you") {
                    ForEach(decisions) { decision in decisionRow(decision) }
                }
            }
            let offers = (desk.report?.contactOffers ?? []).filter { offer in !RecipientStore.shared.all.contains { $0.link == offer.link } }
            if !offers.isEmpty {
                Section("Contacts offered to you") {
                    ForEach(offers) { offer in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(offer.name).font(.headline)
                            if let why = offer.why { Text(why).font(.callout).foregroundStyle(.secondary) }
                            Text("From \(offer.from). Adding it lets you send notes to it; it cannot read anything of yours.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Add to Contacts") {
                                if RecipientStore.shared.add(name: offer.name, text: offer.link) { UsageLog.shared.action("inbox.contact-added") }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if !nextSteps.isEmpty {
                Section("What happens next") {
                    ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                        Label(step, systemImage: "\(index + 1).circle")
                    }
                }
            }
            Section("Your memos, and what came of them") {
                if sentNotes.isEmpty {
                    Text("Nothing sent yet. Record a note for Claude, or press the green button on any screen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sentNotes) { note in memoRow(note) }
            }
            let loose = replies.filter { reply in reply.replyTo == nil || !sentNotes.contains { $0.id == reply.replyTo } }
            if !loose.isEmpty {
                Section("Also from Claude") {
                    ForEach(loose.sorted { $0.at > $1.at }) { reply in replyBubble(reply) }
                }
            }
            if let problem = desk.problem {
                Section { Text(problem).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Inbox")
        .refreshable { await desk.refresh(book: book) }
        .task { await desk.refresh(book: book) }
        .toolbar {
            ToolbarItem { Button { Task { await desk.refresh(book: book) } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        }
    }

    private func decisionRow(_ decision: AgentsReport.Decision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(decision.title).font(.headline)
            if let detail = decision.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            if let chosen = desk.answered[decision.id] {
                Label("You chose: \(chosen). Sent to Claude, sealed.", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.green)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { options(decision) }
                    VStack(alignment: .leading) { options(decision) }
                }
            }
            Text("From \(decision.from), \(decision.at.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func options(_ decision: AgentsReport.Decision) -> some View {
        ForEach(decision.options, id: \.self) { choice in
            Button(choice) { Task { await desk.answer(decision, with: choice) } }
                .buttonStyle(.bordered)
                .disabled(desk.sending)
        }
    }

    private func memoRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text(note.title).font(.callout.weight(.semibold)).lineLimit(3)
            }
            Text(note.stateLine).font(.caption).foregroundStyle(.secondary)
            let answers = replies.filter { $0.replyTo == note.id }.sorted { $0.at < $1.at }
            if answers.isEmpty {
                Text(note.sends?.isEmpty == false ? "No answer yet." : "Not sent yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(answers) { reply in replyBubble(reply) }
        }
        .padding(.vertical, 4)
    }

    private func replyBubble(_ reply: AgentsReport.Message) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reply.text).font(.callout)
            Text("Claude, " + reply.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
