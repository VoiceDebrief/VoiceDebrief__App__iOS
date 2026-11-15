import SwiftUI

/// One turn laid out in its three steps: what kind of thing was asked, the walk through the app's
/// data, and the answer built from what the walk kept. Shared by L05 and L06.
struct LabAskTurnSections: View {
    let turn: LabAskTurn
    @State private var showPassed = false

    var body: some View {
        Section {
            Text(turn.question).font(.callout.weight(.medium)).textSelection(.enabled)
            LabeledContent("The word lists read it as", value: turn.rules?.words ?? "Nothing they know")
            LabeledContent("The model read it as", value: modelWords)
            LabeledContent("Used", value: usedWords)
        } header: {
            Text("1. What kind of thing is asked")
        } footer: {
            Text("The model's reading is used when it called a tool; otherwise the word lists'. A name is kept only if it is one of your contacts or agents.")
        }

        Section {
            if turn.steps.isEmpty {
                Text("Nothing was walked: neither engine could tell what was asked.").foregroundStyle(.secondary)
            }
            ForEach(turn.steps.filter { $0.mark != .passed }) { step in
                LabWalkRow(step: step)
            }
            let passed = turn.steps.filter { $0.mark == .passed }
            if !passed.isEmpty {
                DisclosureGroup("\(passed.count) looked at and passed over", isExpanded: $showPassed) {
                    ForEach(passed) { step in
                        LabWalkRow(step: step)
                    }
                }
                .font(.footnote)
            }
        } header: {
            Text("2. The walk through your data")
        } footer: {
            Text("The code does the looking, not the model. A branch is entered or left closed; inside one, each thing either fits every limit of the question or is passed over, with the reason.")
        }

        Section {
            Text(turn.shown).textSelection(.enabled)
            if turn.spoken != turn.shown {
                LabeledContent("Said aloud", value: "The first \(LabAnswer.spokenLimit) only")
            }
            Text(turn.notice).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        } header: {
            Text("3. The answer")
        } footer: {
            Text("Every line of the answer is a thing the walk kept. The code puts the sentences together; the model writes none of them.")
        }
    }

    private var modelWords: String {
        guard turn.modelAsked else { return "Not asked" }
        if let error = turn.record?.error { return "Could not answer: \(error.words)" }
        let time = turn.modelMs.map { ", in " + Timecode.duration(seconds: $0 / 1000) } ?? ""
        return (turn.model?.words ?? "No tool called") + time
    }

    private var usedWords: String {
        switch turn.used {
        case "model": return "The model's reading"
        case "rules": return "The word lists' reading"
        default: return "Neither"
        }
    }
}

/// One node of the walk, indented by its depth, with its mark and the reason.
struct LabWalkRow: View {
    let step: LabWalkStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(colour).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(step.mark == .matched ? .callout.weight(.medium) : .footnote)
                    .foregroundStyle(step.mark == .skipped || step.mark == .passed ? Color.secondary : Color.primary)
                    .lineLimit(3)
                Text(step.why).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(step.depth) * 16)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch step.mark {
        case .entered: return "folder.fill"
        case .skipped: return "folder"
        case .matched: return "checkmark.circle.fill"
        case .passed: return "circle"
        }
    }

    private var colour: Color {
        switch step.mark {
        case .entered: return .accentColor
        case .matched: return .green
        case .skipped, .passed: return .secondary
        }
    }
}

/// One turn on its own screen, with everything that passed through the model door for it.
struct LabAskTurnView: View {
    let turn: LabAskTurn
    let device: LabDevice

    var body: some View {
        List {
            LabAskTurnSections(turn: turn)
            if let record = turn.record {
                LabRunSections(run: LabRun(id: "turn-\(turn.number)", experiment: "L06", device: device, record: record), title: "The model's turn")
            }
        }
        .readableWidth()
        .navigationTitle("Turn \(turn.number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Experiment L06, task discovery: ask a question about your own data and see it answered in three
/// steps: what kind of thing is asked, the walk through the data, the answer built from what was found.
struct LabDiscoveryView: View {
    let store: NoteStore
    private let desk = LabAskDesk.discovery
    @State private var question = LabAskPrompt.presets[0]

    var body: some View {
        @Bindable var desk = desk
        List {
            Section {
                Menu {
                    ForEach(LabAskPrompt.presets, id: \.self) { preset in
                        Button(preset) { question = preset }
                    }
                } label: {
                    Label("A question kept ready", systemImage: "list.bullet")
                }
                TextField("Ask about your notes, tasks, what you sent", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                Toggle("Ask the model what kind of thing it is", isOn: $desk.askModel)
                if desk.busy {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Answering")
                    }
                } else {
                    Button {
                        Task { await desk.ask(question, source: LabAskPrompt.presets.contains(question) ? "preset" : "typed") }
                    } label: {
                        Label("Ask", systemImage: "questionmark.bubble")
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Question")
            } footer: {
                Text("Model: \(OnDeviceModel.status.text). The model is asked one thing, in a new session: which kind of thing the question is about. It is not shown your data. With the switch off, the word lists alone decide.")
            }

            if let latest = desk.turns.first {
                LabAskTurnSections(turn: latest)
            }

            if !desk.turns.isEmpty {
                Section {
                    ForEach(desk.turns) { turn in
                        NavigationLink {
                            LabAskTurnView(turn: turn, device: desk.log.device)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(turn.question).lineLimit(2)
                                Text(turn.notice).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ShareLink(item: desk.log.json) {
                        Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the log", role: .destructive) { desk.clear() }
                } header: {
                    Text("Every turn")
                } footer: {
                    Text("Kept only while the app is open. The JSON holds each question, the walk and the answer, which includes words of your notes and of messages from agents.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Task discovery")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { desk.world = { [store] in LabAskDesk.world(store: store) } }
    }
}

/// Experiment L05, talk back: ask by voice, hear the answer. The same three steps as L06 answer
/// each question; here they are a conversation.
struct LabTalkView: View {
    let store: NoteStore
    private let talk = LabTalkBack.shared
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var typed = ""

    var body: some View {
        @Bindable var talk = talk
        @Bindable var desk = talk.desk
        List {
            Section {
                Button {
                    Task {
                        if talk.running { await talk.stop() } else { await talk.start(localeId: localeId) }
                    }
                } label: {
                    Label(talk.running ? "End the conversation" : "Start talking", systemImage: talk.running ? "stop.circle" : "mic.circle")
                }
                Label(talk.state.words, systemImage: stateSymbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(talk.state == .idle ? Color.secondary : Color.primary)
                if let problem = talk.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                if talk.state == .listening {
                    LabLiveStrip(listening: true, settled: talk.settled, volatile: talk.volatile)
                }
                HStack {
                    TextField("Or type a question", text: $typed)
                        .onSubmit(sendTyped)
                    Button("Ask", action: sendTyped)
                        .buttonStyle(.borderless)
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || talk.state == .thinking || talk.state == .speaking)
                }
                Toggle("Say the answers aloud", isOn: $talk.speakAnswers)
                Toggle("Ask the model what kind of thing it is", isOn: $desk.askModel)
            } header: {
                Text("Conversation")
            } footer: {
                Text("It listens for one question, stops listening, answers, says the answer, and listens again: it does not listen while it speaks. Nothing is said aloud while a note is being recorded. Model: \(OnDeviceModel.status.text).")
            }

            if desk.turns.isEmpty {
                Section {
                    Text("Ask what your tasks are, what happened with a memo you sent, what is waiting for you, or what someone said.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(desk.turns) { turn in
                        NavigationLink {
                            LabAskTurnView(turn: turn, device: desk.log.device)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(turn.question, systemImage: "person.wave.2").font(.callout.weight(.medium))
                                Label(turn.spoken, systemImage: "speaker.wave.2").font(.callout)
                                Text(turn.notice).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    ShareLink(item: desk.log.json) {
                        Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the log", role: .destructive) { desk.clear() }
                } header: {
                    Text("What was asked and answered")
                } footer: {
                    Text("Newest first. Tap a turn to see how it was answered. Kept only while the app is open; the JSON includes words of your notes and of messages from agents.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Talk back")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { desk.world = { [store] in LabAskDesk.world(store: store) } }
        .onDisappear {
            Task { await talk.stop() }
        }
    }

    private var stateSymbol: String {
        switch talk.state {
        case .idle: return "moon.zzz"
        case .listening: return "ear"
        case .thinking: return "hourglass"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private func sendTyped() {
        let question = typed
        typed = ""
        Task { await talk.type(question) }
    }
}
