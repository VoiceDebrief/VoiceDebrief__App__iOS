import SwiftUI

/// The Lab: small experiments run on this device, each showing everything it did.
struct LabView: View {
    let store: NoteStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LabOnePromptView(store: store)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("L01: One prompt, tools on and off")
                        Text("One request to Apple's on-device model with the tools you choose, and the full record of it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Experiments")
            } footer: {
                Text("An experiment changes nothing: its tools only read, and what the model chooses is shown, not acted on.")
            }
            Section("Apple's on-device model") {
                LabeledContent("Status", value: OnDeviceModel.status.text)
                LabeledContent("Context", value: OnDeviceModel.contextSize.map { "\($0) tokens" } ?? "Not known")
            }
        }
        .navigationTitle("Lab")
    }
}

/// Experiment L01: type or pick a prompt, switch tools on and off, run one request, see all of it.
struct LabOnePromptView: View {
    let store: NoteStore
    private let lab = LabSession.shared
    @State private var presetId: String?
    @State private var instructions = LabDefaults.instructions
    @State private var prompt = LabPreset.all[0].prompt
    @State private var tools = Set(LabToolId.allCases)

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: $presetId) {
                    Text("My own prompt").tag(String?.none)
                    ForEach(LabPreset.all) { preset in
                        Text(preset.title).tag(String?.some(preset.id))
                    }
                }
                TextField("Prompt", text: $prompt, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Prompt")
            } footer: {
                Text(presetFooter)
            }
            .onChange(of: presetId) { _, new in
                guard let preset = LabPreset.find(new) else { return }
                prompt = preset.prompt
                tools = preset.tools
            }

            Section("Instructions") {
                TextField("Instructions", text: $instructions, axis: .vertical)
                    .lineLimit(2...8)
                    .font(.callout)
            }

            Section {
                ForEach(LabToolId.allCases) { tool in
                    Toggle(isOn: binding(for: tool)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title)
                            Text(tool.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tools offered")
            } footer: {
                Text("A tool that is off is not offered to the model at all. None of these tools changes anything.")
            }

            Section {
                if lab.running {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Asking the model")
                    }
                } else {
                    Button {
                        Task {
                            await lab.run(presetId: presetId, instructions: instructions, prompt: prompt, tools: tools, store: store)
                        }
                    } label: {
                        Label("Run once", systemImage: "play.circle")
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } footer: {
                Text("Model: \(OnDeviceModel.status.text). Each run is a new session with no history.")
            }

            if let latest = lab.runs.first {
                LabRunSections(run: latest, title: "Latest run")
            }

            let tally = LabTally.of(lab.runs)
            if !tally.isEmpty {
                Section {
                    ForEach(tally) { row in
                        LabeledContent(row.title, value: "\(row.right) of \(row.runs)")
                    }
                } header: {
                    Text("Tool choice as expected")
                } footer: {
                    Text("Counted over the runs below. Only the choice of tool is counted, not whether the answer is good.")
                }
            }

            if !lab.runs.isEmpty {
                Section {
                    ForEach(lab.runs) { run in
                        NavigationLink {
                            LabRunView(run: run)
                        } label: {
                            LabRunRow(run: run)
                        }
                    }
                    ShareLink(item: LabRun.json(of: lab.runs)) {
                        Label("Share all runs as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the runs", role: .destructive) { lab.clear() }
                } header: {
                    Text("Runs since the app opened")
                } footer: {
                    Text("Runs are kept only while the app is open. The JSON holds everything shown here, including any words of your notes that a tool returned.")
                }
            }
        }
        .navigationTitle("One prompt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presetFooter: String {
        guard let preset = LabPreset.find(presetId) else {
            return "A preset fills in the prompt and the tools, and says which tools a reliable model would call."
        }
        if preset.expects.isEmpty { return "Expected: no tool call." }
        let names = preset.expects.map(\.rawValue).joined(separator: ", ")
        if preset.expects.contains(where: { !tools.contains($0) }) {
            return "Needs \(names), which is switched off. Expected: no tool call, and an answer that says it cannot know."
        }
        return "Expected tool calls: \(names)."
    }

    private func binding(for tool: LabToolId) -> Binding<Bool> {
        Binding(
            get: { tools.contains(tool) },
            set: { on in
                if on { tools.insert(tool) } else { tools.remove(tool) }
            })
    }
}

/// One line for a run in the list: the prompt, the tools called, the time.
struct LabRunRow: View {
    let run: LabRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.record.prompt).lineLimit(2)
            Text(summary)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(run.record.error == nil ? Color.secondary : Color.red)
        }
    }

    private var summary: String {
        let calls = run.calledTools.isEmpty ? "no tool call" : run.calledTools.joined(separator: ", ")
        let time = Timecode.duration(seconds: run.record.totalMs / 1000)
        if let error = run.record.error { return "\(error.kind) · \(calls) · \(time)" }
        return "\(calls) · \(time)"
    }
}

/// One run on its own screen, with the export.
struct LabRunView: View {
    let run: LabRun

    var body: some View {
        List {
            LabRunSections(run: run, title: "Run")
            Section {
                ShareLink(item: run.json) {
                    Label("Share this run as JSON", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("The JSON holds everything on this screen, including any words of your notes that a tool returned.")
            }
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Everything that passed through the model door for one run.
struct LabRunSections: View {
    let run: LabRun
    let title: String

    var body: some View {
        Section(title) {
            if let error = run.record.error {
                Label(error.words, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                if !error.raw.isEmpty {
                    Text(error.raw).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if let answer = run.record.answer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Answer").font(.caption).foregroundStyle(.secondary)
                    Text(answer).textSelection(.enabled)
                }
            }
            LabeledContent("Total time", value: Timecode.duration(seconds: run.record.totalMs / 1000))
            if let verdict = run.verdict {
                LabeledContent("Tool choice", value: verdict.words)
            }
            if let screen = run.screenChoice {
                LabeledContent("Screen chosen (not acted on)", value: screen)
            }
        }

        Section("Tool calls") {
            if run.record.toolCalls.isEmpty {
                Text("The model called no tool.").foregroundStyle(.secondary)
            }
            ForEach(run.record.toolCalls) { call in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(call.order). \(call.name)").font(.footnote.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f ms", call.durationMs))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(arguments(call)).font(.footnote.monospaced())
                    Text(call.result)
                        .font(.footnote)
                        .foregroundStyle(call.ok ? Color.secondary : Color.orange)
                        .textSelection(.enabled)
                }
            }
            if run.record.modelToolRequests != run.calledTools {
                LabeledContent("Asked for, by the session's transcript",
                               value: run.record.modelToolRequests.isEmpty ? "Nothing" : run.record.modelToolRequests.joined(separator: ", "))
            }
        }

        Section("What the model was given") {
            block("Instructions", run.record.instructions.isEmpty ? "(none)" : run.record.instructions)
            block("Prompt", run.record.prompt)
            ForEach(run.record.toolsOffered, id: \.name) { tool in
                block("Tool offered: \(tool.name)", tool.description)
            }
            if !run.record.toolsWithheld.isEmpty {
                block("Tools not offered", run.record.toolsWithheld.joined(separator: ", "))
            }
        }

        if !run.record.transcript.isEmpty {
            Section {
                DisclosureGroup("The session's transcript, \(run.record.transcript.count) entries") {
                    ForEach(Array(run.record.transcript.enumerated()), id: \.offset) { _, entry in
                        Text(entry).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }

        Section("Device") {
            LabeledContent("App", value: run.device.appVersion)
            LabeledContent("System", value: run.device.system)
            LabeledContent("Machine", value: run.device.machine)
            LabeledContent("Context", value: run.device.modelContextSize.map { "\($0) tokens" } ?? "Not known")
        }
    }

    private func arguments(_ call: ModelDoorToolCall) -> String {
        if call.arguments.isEmpty { return "(no arguments)" }
        return call.arguments.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    private func block(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.callout).textSelection(.enabled)
        }
    }
}
