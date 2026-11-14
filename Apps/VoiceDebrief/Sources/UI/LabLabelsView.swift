import SwiftUI

/// Experiment L04, live labels: speak a note and watch a small set of labels fill in, every few
/// seconds, from the words so far. Say what a label is and it stays that way.
struct LabLabelsView: View {
    private let desk = LabLabelsDesk.shared
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var typed = ""
    @State private var editing: LabLabelField?

    var body: some View {
        @Bindable var desk = desk
        List {
            Section {
                Button {
                    Task {
                        if desk.running { await desk.stop() } else { await desk.start(localeId: localeId) }
                    }
                } label: {
                    Label(desk.running ? "Stop" : "Start speaking", systemImage: desk.running ? "stop.circle" : "mic.circle")
                }
                if let problem = desk.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                if desk.running || !desk.transcript.isEmpty {
                    LabLiveStrip(listening: desk.running, settled: [desk.typed, desk.settled].filter { !$0.isEmpty }.joined(separator: " "),
                                 volatile: desk.volatile.isEmpty ? "" : " " + desk.volatile)
                }
                HStack {
                    TextField("Or type what is said", text: $typed)
                        .onSubmit(sendTyped)
                    Button("Add", action: sendTyped)
                        .buttonStyle(.borderless)
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("The note")
            } footer: {
                Text("This experiment keeps no recording and no note: only the words, while this screen is open. Model: \(OnDeviceModel.status.text).")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(desk.inUse) { field in
                        Button {
                            editing = field
                        } label: {
                            LabLabelChip(field: field, value: desk.board.values[field.id], pinned: desk.board.isPinned(field.id),
                                         changed: desk.lastChanged.contains(field.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                if let latest = desk.loops.first {
                    Label(latest.notice, systemImage: latest.record.error == nil ? "timer" : "exclamationmark.triangle")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(latest.record.error == nil ? Color.secondary : Color.red)
                } else if desk.looping {
                    Label("Asking the model for the first time", systemImage: "timer").font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        Task { await desk.loop(force: true) }
                    } label: {
                        Label(desk.looping ? "Asking the model" : "Ask the model now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(desk.looping || desk.transcript.isEmpty)
                    Spacer()
                    Button("New note") { desk.startAgain() }
                        .buttonStyle(.borderless)
                        .disabled(desk.running)
                }
            } header: {
                Text("Labels")
            } footer: {
                Text("A label with a pin is one you set, by saying so (the topic is, the title is, this is a memo for, this is urgent) or by tapping it. The model does not move a pinned label. Tap a label to set it yourself or to let the model fill it again.")
            }

            Section {
                ForEach(LabLabelField.all.filter { !$0.always }) { field in
                    Toggle(field.title, isOn: Binding(
                        get: { desk.chosen.contains(field.id) },
                        set: { desk.setChosen(field.id, $0) }))
                }
                Picker("Ask the model every", selection: $desk.seconds) {
                    ForEach(LabLabelsDesk.secondsChoices, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                Picker("Words sent each time", selection: $desk.windowTokens) {
                    ForEach(LabLabelsDesk.windowChoices, id: \.self) { tokens in
                        Text(tokens == 0 ? "Everything so far" : "The last \(tokens) tokens or so").tag(tokens)
                    }
                }
            } header: {
                Text("Which labels, and how often")
            } footer: {
                Text("For, Topic, Title and Urgency are always on. A token is counted as four characters, which is a rule of thumb. Sending everything will, on a long note, be more than the model can take: the loop then says so.")
            }

            if !desk.overrides.isEmpty {
                Section("Set by you") {
                    ForEach(Array(desk.overrides.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(LabLabelField.find(entry.field)?.title ?? entry.field): \(entry.value)")
                            Text(entry.sentence).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }

            if !desk.loops.isEmpty {
                Section {
                    ForEach(desk.loops) { loop in
                        NavigationLink {
                            LabLabelLoopView(loop: loop, device: desk.log.device)
                        } label: {
                            Text(loop.notice).font(.footnote.monospacedDigit())
                        }
                    }
                    ShareLink(item: desk.log.json) {
                        Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the log", role: .destructive) { desk.clearLog() }
                } header: {
                    Text("Every loop")
                } footer: {
                    Text("Kept only while the app is open. The JSON holds the words sent on every loop, word for word, and the names of your contacts.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Live labels")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { field in
            LabLabelEditSheet(field: field, value: desk.board.values[field.id]?.text ?? "", pinned: desk.board.isPinned(field.id),
                              save: { desk.setByHand(field.id, $0) }, unpin: { desk.unpin(field.id) })
        }
        .onAppear { desk.candidates = LabLabelsView.candidates() }
        .onDisappear {
            Task { await desk.stop() }
        }
    }

    private func sendTyped() {
        desk.type(typed)
        typed = ""
    }

    /// Everyone a note can be for: the contacts, then the agents in the last agents report.
    static func candidates() -> [LabLabelCandidate] {
        let contacts = RecipientStore.shared.all.map {
            LabLabelCandidate(id: $0.link, name: $0.name, kind: $0.name == RecipientStore.builtInName ? "conductor" : "person")
        }
        let agents = (AgentsDesk.shared.report?.agents ?? []).map { LabLabelCandidate(id: $0.id, name: $0.name, kind: $0.kind) }
        return contacts + agents.filter { agent in !contacts.contains { $0.name == agent.name } }
    }
}

/// One label in the grid: its name, what it holds, who set it, and a mark when the newest loop changed it.
struct LabLabelChip: View {
    let field: LabLabelField
    let value: LabLabelValue?
    let pinned: Bool
    let changed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
            }
            HStack(spacing: 8) {
                if let matched = value?.matched {
                    AvatarView(id: matched.id, kind: LabLabelChip.avatarKind(matched.kind), size: 28)
                }
                Text(value?.text ?? "Not yet")
                    .font(.callout.weight(value == nil ? .regular : .medium))
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(origin).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(changed ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(pinned ? Color.orange : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var origin: String {
        guard let value else { return "Waiting for the words" }
        var text: String
        switch value.source {
        case "voice": text = "You said so"
        case "hand": text = "You set it"
        default: text = value.loop.map { "The model, loop \($0)" } ?? "The model"
        }
        if field.kind == .person, value.matched == nil { text += ". No contact or agent has this name" }
        return text
    }

    static func avatarKind(_ kind: String) -> AvatarKind {
        kind == "person" ? .person : AvatarKind(agentKind: kind)
    }
}

/// Sets a label by hand, or hands it back to the model.
struct LabLabelEditSheet: View {
    let field: LabLabelField
    let value: String
    let pinned: Bool
    let save: (String) -> Void
    let unpin: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if case .choice(let options) = field.kind {
                        Picker(field.title, selection: $text) {
                            Text("Not set").tag("")
                            ForEach(options, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } else {
                        TextField(field.title, text: $text)
                    }
                } footer: {
                    Text("What you set here is pinned: the model will not change it.")
                }
                if pinned {
                    Section {
                        Button("Let the model fill this again") {
                            unpin()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        save(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = value }
        }
    }
}

/// One loop on its own screen: what the model offered for each label, what the board did with it,
/// and everything that passed through the model door.
struct LabLabelLoopView: View {
    let loop: LabLabelLoop
    let device: LabDevice

    var body: some View {
        List {
            Section("Loop \(loop.number)") {
                LabeledContent("To the first label", value: loop.firstCallMs.map { Timecode.duration(seconds: $0 / 1000) } ?? "None offered")
                LabeledContent("In all", value: Timecode.duration(seconds: loop.totalMs / 1000))
                LabeledContent("Sent, about", value: "\(loop.aboutTokensIn) tokens")
                LabeledContent("Window", value: loop.windowTokens == 0 ? "Everything so far" : "The last \(loop.windowTokens) tokens or so")
                LabeledContent("Words sent", value: "\(loop.windowCharacters) of \(loop.transcriptCharacters) characters")
            }
            Section("Offered") {
                if loop.proposals.isEmpty {
                    Text("The model offered no label.").foregroundStyle(.secondary)
                }
                ForEach(Array(loop.proposals.enumerated()), id: \.offset) { _, proposal in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(LabLabelField.find(proposal.field)?.title ?? proposal.field): \(proposal.value)")
                        Text(LabLabelLoopView.words(proposal)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            LabRunSections(run: LabRun(id: "loop-\(loop.number)", experiment: "L04", device: device, record: loop.record), title: "The model's turn")
        }
        .readableWidth()
        .navigationTitle("Loop \(loop.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func words(_ proposal: LabLabelProposal) -> String {
        let when = proposal.atMs.map { ", " + Timecode.duration(seconds: $0 / 1000) + " in" } ?? ""
        switch proposal.outcome {
        case .changed: return "The label took it" + when
        case .same: return "The label already held it" + when
        case .pinned: return "Not taken: you set this label" + when
        case .rejected: return "Not taken: not a value this label can hold" + when
        }
    }
}
