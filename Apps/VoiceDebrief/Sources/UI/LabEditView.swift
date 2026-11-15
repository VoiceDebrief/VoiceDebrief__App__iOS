import SwiftUI
import UIKit

/// Experiment L07, edit with Apple Intelligence: a text, a request in your own words, and the
/// model's proposal shown as a change you accept or reject.
struct LabEditView: View {
    let store: NoteStore
    private let desk = LabEditDesk.shared
    @State private var request = LabEditPrompt.presets[0]

    var body: some View {
        @Bindable var desk = desk
        List {
            Section {
                TextEditor(text: $desk.text)
                    .frame(minHeight: 140)
                    .disabled(desk.busy || desk.waiting != nil)
                HStack {
                    Menu {
                        ForEach(notes) { note in
                            Button(note.title) { desk.text = note.run.transcript?.lines.map(\.text).joined(separator: " ") ?? "" }
                        }
                    } label: {
                        Label("A note's words", systemImage: "tray.full")
                    }
                    .disabled(notes.isEmpty)
                    Spacer()
                    Button {
                        if let pasted = UIPasteboard.general.string { desk.text = pasted }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                }
                .disabled(desk.busy || desk.waiting != nil)
            } header: {
                Text("Text")
            } footer: {
                Text("A copy to work on. A note whose words are brought in here is not changed, whatever you accept. \(LabDiff.tokens(desk.text).count) words.")
            }

            Section {
                TextField("What to do with it", text: $request, axis: .vertical)
                    .lineLimit(1...3)
                Menu {
                    ForEach(LabEditPrompt.presets, id: \.self) { preset in
                        Button(preset) { request = preset }
                    }
                } label: {
                    Label("A request kept ready", systemImage: "list.bullet")
                }
                if desk.busy {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("The model is editing")
                    }
                } else {
                    Button {
                        Task { await desk.propose(request) }
                    } label: {
                        Label("Propose the change", systemImage: "wand.and.stars")
                    }
                    .disabled(desk.waiting != nil || desk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Request")
            } footer: {
                Text("Model: \(OnDeviceModel.status.text). One request, in a new session, with no tools: the model is given the text and the request and replies with the edited text.")
            }

            if let latest = desk.turns.first {
                LabEditTurnSections(turn: latest, accept: { desk.accept(latest.number) }, reject: { desk.reject(latest.number) },
                                    undo: desk.text == latest.after && latest.state == .accepted ? { desk.undo(latest.number) } : nil)
            }

            if !desk.turns.isEmpty {
                Section {
                    ForEach(desk.turns) { turn in
                        NavigationLink {
                            LabEditTurnView(turn: turn, device: desk.log.device)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(turn.request).lineLimit(2)
                                Text("\(LabEditTurnSections.words(turn.state)). \(turn.notice)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ShareLink(item: desk.log.json) {
                        Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear the log", role: .destructive) { desk.clear() }
                } header: {
                    Text("Every edit")
                } footer: {
                    Text("Kept only while the app is open. The JSON holds each text before and after, word for word.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { desk.names = RecipientStore.shared.all.map(\.name) }
    }

    private var notes: [Note] {
        Array(store.notes.filter { !($0.run.transcript?.isEmpty ?? true) }.prefix(15))
    }
}

/// A proposed edit: the change, the cautions, and the two answers.
struct LabEditTurnSections: View {
    let turn: LabEditTurn
    var accept: (() -> Void)?
    var reject: (() -> Void)?
    var undo: (() -> Void)?
    @State private var view = "change"

    var body: some View {
        Section {
            if turn.state == .failed {
                Label(turn.record?.error?.words ?? "The model gave no text.", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                Picker("Show", selection: $view) {
                    Text("The change").tag("change")
                    Text("Before").tag("before")
                    Text("After").tag("after")
                }
                .pickerStyle(.segmented)
                switch view {
                case "before": Text(turn.before).textSelection(.enabled)
                case "after": Text(turn.after).textSelection(.enabled)
                default: Text(LabEditTurnSections.attributed(turn.pieces)).textSelection(.enabled)
                }
                ForEach(turn.cautions, id: \.self) { caution in
                    Label(caution, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
                }
            }
            Text(turn.notice).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            if turn.state == .proposed, let accept, let reject {
                HStack(spacing: 16) {
                    Button("Accept", action: accept).buttonStyle(.borderedProminent)
                    Button("Reject", action: reject).buttonStyle(.bordered)
                }
                .controlSize(.small)
            } else if turn.state != .failed {
                LabeledContent("You", value: LabEditTurnSections.words(turn.state))
                if let undo {
                    Button("Put the text back as it was", action: undo).buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Proposed: \(turn.request)")
        } footer: {
            Text("In the change, words struck through in red go and underlined words in green come in. The comparison is made by the app, word by word, not described by the model.")
        }
    }

    static func words(_ state: LabEditTurn.State) -> String {
        switch state {
        case .proposed: return "Waiting for you"
        case .accepted: return "Accepted"
        case .rejected: return "Rejected"
        case .failed: return "No proposal"
        }
    }

    /// The change as one piece of text: what goes is struck through, what comes in is underlined.
    static func attributed(_ pieces: [LabDiffPiece]) -> AttributedString {
        var out = AttributedString()
        for piece in pieces {
            var part = AttributedString(piece.text)
            switch piece.kind {
            case .same: break
            case .removed:
                part.foregroundColor = Color.red
                part.strikethroughStyle = Text.LineStyle.single
            case .added:
                part.foregroundColor = Color.green
                part.underlineStyle = Text.LineStyle.single
            }
            out += part
        }
        return out
    }
}

/// One edit on its own screen, with everything that passed through the model door for it.
struct LabEditTurnView: View {
    let turn: LabEditTurn
    let device: LabDevice

    var body: some View {
        List {
            LabEditTurnSections(turn: turn)
            if let record = turn.record {
                LabRunSections(run: LabRun(id: "edit-\(turn.number)", experiment: "L07", device: device, record: record), title: "The model's turn")
            }
        }
        .readableWidth()
        .navigationTitle("Edit \(turn.number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
