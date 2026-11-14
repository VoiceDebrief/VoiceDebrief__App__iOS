import SwiftUI

/// Experiment L02, the control centre: say, type or replay a sentence; see which action the fixed
/// phrases and the model each propose; confirm, refuse or correct it. Nothing is carried out.
struct LabControlView: View {
    private let centre = LabControlCentre.shared
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var typed = ""
    @State private var editing: LabControlEntry?
    @State private var newPhrase = ""
    @State private var newAction = LabAction.finishRecording.rawValue

    var body: some View {
        @Bindable var centre = centre
        List {
            Section {
                Button {
                    Task {
                        if centre.listening { await centre.stopListening() } else { await centre.startListening(localeId: localeId) }
                    }
                } label: {
                    Label(centre.listening ? "Stop listening" : "Listen", systemImage: centre.listening ? "stop.circle" : "mic.circle")
                }
                if centre.listening || !centre.liveSettled.isEmpty {
                    Text(liveWords)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.head)
                }
                if let problem = centre.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                HStack {
                    TextField("Or type a sentence", text: $typed)
                        .onSubmit(sendTyped)
                    Button("Ask", action: sendTyped)
                        .buttonStyle(.borderless)
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Toggle("Ask the model as well as the phrases", isOn: $centre.askModel)
            } header: {
                Text("Words in")
            } footer: {
                Text("Model: \(OnDeviceModel.status.text). Each sentence is one question to the model, in a new session, with one tool for each action.")
            }

            Section {
                let cards = centre.entries.filter { $0.state != .nothing }
                if cards.isEmpty {
                    Text("No action proposed yet.").foregroundStyle(.secondary)
                }
                ForEach(cards) { entry in
                    LabControlCard(entry: entry,
                                   doIt: { centre.doIt(entry.id) },
                                   notThis: { centre.notThis(entry.id) },
                                   edit: { editing = entry })
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Do it records your choice. This experiment carries no action out: nothing is recorded, sent, saved or opened.")
            }

            Section {
                ForEach(centre.triggers) { trigger in
                    LabeledContent(trigger.phrase, value: LabAction.title(for: trigger.action))
                }
                .onDelete { centre.removeTriggers(at: $0) }
                HStack {
                    TextField("A new phrase", text: $newPhrase)
                        .textInputAutocapitalization(.never)
                    Picker("Action", selection: $newAction) {
                        ForEach(LabAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    .labelsHidden()
                    Button("Add") {
                        centre.addTrigger(phrase: newPhrase, action: newAction)
                        newPhrase = ""
                    }
                    .buttonStyle(.borderless)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Put the first list back") { centre.restoreTriggers() }
            } header: {
                Text("Phrases that propose an action")
            } footer: {
                Text("Kept on this device. A phrase with not, never or don't just before it proposes nothing. Swipe a phrase to remove it.")
            }

            Section {
                ForEach(LabAction.allCases) { action in
                    Toggle(action.title, isOn: Binding(
                        get: { centre.automatic.contains(action.rawValue) },
                        set: { centre.setAutomatic(action.rawValue, $0) }))
                }
            } header: {
                Text("Without asking")
            } footer: {
                Text("An action switched on here is marked done as soon as it is proposed. Everything else waits for you.")
            }

            Section {
                let tally = LabControlTally.of(centre.entries)
                LabeledContent("Model: right action", value: "\(tally.modelRight) of \(tally.modelJudged)")
                LabeledContent("Model: a wrong action", value: "\(tally.modelWrongAction)")
                LabeledContent("Model: missed an action", value: "\(tally.modelMissed)")
                LabeledContent("Model: errors", value: "\(tally.modelErrors)")
                LabeledContent("Model: time for a sentence", value: tally.modelMeanMs.map { Timecode.duration(seconds: $0 / 1000) } ?? "Not known")
                LabeledContent("Phrases: right action", value: "\(tally.phraseRight) of \(tally.phraseJudged)")
                if centre.testing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Running the test sentences")
                    }
                } else {
                    Button {
                        Task { await centre.runTests() }
                    } label: {
                        Label("Run the \(LabControlTest.all.count) test sentences", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("Measure")
            } footer: {
                Text("A sentence is judged when it is a test sentence, or when you said Do it, Not this or corrected it. Only the action is judged, not what it applies to.")
            }

            if !centre.entries.isEmpty {
                Section {
                    ForEach(centre.entries) { entry in
                        NavigationLink {
                            LabControlEntryView(entry: entry, device: centre.log.device)
                        } label: {
                            LabControlLogRow(entry: entry)
                        }
                        .swipeActions {
                            Button("Correct") { editing = entry }
                        }
                    }
                    ShareLink(item: centre.log.json) {
                        Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the log", role: .destructive) { centre.clear() }
                } header: {
                    Text("Log")
                } footer: {
                    Text("Kept only while the app is open. The JSON holds every sentence heard here, word for word.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Control centre")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            LabControlEditSheet(entry: entry) { action, argument in
                centre.edit(entry.id, action: action, argument: argument)
            }
        }
        .onDisappear {
            Task { await centre.stopListening() }
        }
    }

    private var liveWords: String {
        let text = (centre.liveSettled + " " + centre.liveVolatile).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Listening" : text
    }

    private func sendTyped() {
        centre.hear(typed, source: "typed")
        typed = ""
    }
}

/// One proposed action in the pipeline: what was said, what is proposed and by which engine, and
/// the three things the person can do about it.
struct LabControlCard: View {
    let entry: LabControlEntry
    let doIt: () -> Void
    let notThis: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.words).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(headline).font(.headline)
                Spacer()
                Text(stateWords).font(.footnote.weight(.semibold)).foregroundStyle(stateColour)
            }
            Text(LabControlWords.engines(entry)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            if entry.state == .waiting {
                HStack(spacing: 16) {
                    Button("Do it", action: doIt).buttonStyle(.borderedProminent)
                    Button("Not this", action: notThis).buttonStyle(.bordered)
                    Button("Edit", action: edit).buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var headline: String {
        if entry.state == .asking { return entry.phrase?.words ?? "Asking the model" }
        return (entry.chosen ?? entry.proposal)?.words ?? "No action"
    }

    private var stateWords: String {
        switch entry.state {
        case .asking: return "Asking"
        case .waiting: return "Waiting for you"
        case .done: return entry.automatic ? "Done, without asking" : (entry.edited ? "Corrected" : "Done")
        case .notThis: return "Not this"
        case .nothing: return "Nothing"
        }
    }

    private var stateColour: Color {
        switch entry.state {
        case .asking: return .secondary
        case .waiting: return .orange
        case .done: return .green
        case .notThis: return .red
        case .nothing: return .secondary
        }
    }
}

enum LabControlWords {
    /// What each engine proposed, on one line.
    static func engines(_ entry: LabControlEntry) -> String {
        let phrase = entry.phrase.map { "Phrase: \($0.words)" } ?? "Phrase: nothing"
        guard entry.modelAsked else { return phrase + " · Model: not asked" }
        if entry.state == .asking { return phrase + " · Model: asking" }
        if let error = entry.record?.error { return phrase + " · Model: \(error.kind)" }
        let time = entry.modelMs.map { ", " + Timecode.duration(seconds: $0 / 1000) } ?? ""
        return phrase + " · Model: " + (entry.model?.words ?? "nothing") + time
    }

    static func verdict(_ right: Bool?) -> String {
        switch right {
        case .some(true): return "Right"
        case .some(false): return "Wrong"
        case .none: return "Not judged"
        }
    }
}

/// One sentence in the log, whether or not it proposed anything.
struct LabControlLogRow: View {
    let entry: LabControlEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.words).lineLimit(2)
            Text(LabControlWords.engines(entry)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            if entry.truth != nil {
                Text("Model: \(LabControlWords.verdict(entry.modelVerdict)) · Phrases: \(LabControlWords.verdict(entry.phraseVerdict))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One sentence on its own screen, with everything that passed through the model door for it.
struct LabControlEntryView: View {
    let entry: LabControlEntry
    let device: LabDevice

    var body: some View {
        List {
            Section("Sentence") {
                Text(entry.words).textSelection(.enabled)
                LabeledContent("Came in", value: entry.source)
                if let expected = entry.expected {
                    LabeledContent("The test expects", value: LabAction.title(for: expected))
                }
                LabeledContent("Phrases proposed", value: entry.phrase?.words ?? "Nothing")
                if let matched = entry.phraseMatched {
                    LabeledContent("Phrase heard", value: matched)
                }
                LabeledContent("Model proposed", value: entry.modelAsked ? (entry.model?.words ?? "Nothing") : "Not asked")
                if entry.modelCalls.count > 1 {
                    LabeledContent("Every tool it called", value: entry.modelCalls.joined(separator: ", "))
                }
                LabeledContent("You chose", value: chosenWords)
                LabeledContent("Model", value: LabControlWords.verdict(entry.modelVerdict))
                LabeledContent("Phrases", value: LabControlWords.verdict(entry.phraseVerdict))
            }
            if let record = entry.record {
                LabRunSections(run: LabRun(id: entry.id, experiment: "L02", device: device, record: record), title: "The model's turn")
            }
        }
        .readableWidth()
        .navigationTitle("Sentence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chosenWords: String {
        switch entry.state {
        case .asking: return "The model is being asked"
        case .waiting: return "Not yet"
        case .done: return (entry.chosen?.words ?? "") + (entry.automatic ? " (without asking)" : "")
        case .notThis: return entry.edited ? "No action" : "Not this"
        case .nothing: return entry.edited ? "No action" : "Nothing to choose"
        }
    }
}

/// Says what a sentence did ask for: an action and what it applies to, or no action.
struct LabControlEditSheet: View {
    let entry: LabControlEntry
    let save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var action = LabAction.none
    @State private var argument = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Sentence") {
                    Text(entry.words)
                }
                Section("What it asked for") {
                    Picker("Action", selection: $action) {
                        Text("No action").tag(LabAction.none)
                        ForEach(LabAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    if let name = LabAction(rawValue: action)?.argumentName {
                        TextField(name, text: $argument)
                    }
                }
            }
            .navigationTitle("Correct")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(action, LabAction(rawValue: action)?.argumentName == nil ? "" : argument)
                        dismiss()
                    }
                }
            }
            .onAppear {
                action = (entry.chosen ?? entry.proposal)?.action ?? LabAction.none
                argument = (entry.chosen ?? entry.proposal)?.argument ?? ""
            }
        }
    }
}
