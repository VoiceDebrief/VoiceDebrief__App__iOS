import SwiftUI

/// What a note holds: the debrief, the transcript, sharing, and how each step went.
struct RunSections: View {
    let run: DebriefRun

    var body: some View {
        if let debrief = run.debrief {
            Section {
                ForEach(Array(DebriefMarkdown.blocks(debrief).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let text):
                        Text(text).font(.headline).padding(.top, 4)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(text)
                        }
                    case .paragraph(let text):
                        Text(text)
                    }
                }
                .listRowSeparator(.hidden)
                .textSelection(.enabled)
            } header: {
                Text("Debrief")
            } footer: {
                Text("Written by a model, not a stenographer. It can mishear, and it can add things nobody said. Check anything that matters against the audio.")
            }
        }

        if let transcript = run.transcript, !transcript.isEmpty {
            Section("Transcript") {
                ForEach(transcript.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Timecode.format(ms: line.startMs))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(line.text)
                    }
                    .textSelection(.enabled)
                }
            }
            Section {
                ShareLink(item: run.markdown) {
                    Label("Share the debrief and transcript", systemImage: "square.and.arrow.up")
                }
            }
        }

        Section("Details") {
            LabeledContent("Source", value: run.source)
            if let seconds = run.audioSeconds {
                LabeledContent("Audio", value: Timecode.duration(seconds: seconds))
            }
            ForEach(run.steps) { step in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step.name)
                        Spacer()
                        Text(step.outcome == .running ? "Working" : Timecode.duration(seconds: step.seconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if !step.note.isEmpty {
                        Text(step.note)
                            .font(.footnote)
                            .foregroundStyle(step.outcome == .done ? Color.secondary : Color.orange)
                    }
                }
            }
        }
    }
}

enum LocaleNames {
    /// "English (United Kingdom)" for "en-GB", in the device's own language.
    static func name(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }
}

/// The microphone's recent loudness as moving bars: the sign that the recording is being heard.
struct LevelBars: View {
    let levels: [Double]
    var height: CGFloat = 30
    var barWidth: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.red.opacity(0.35 + 0.65 * level))
                    .frame(width: barWidth, height: 4 + (height - 6) * level)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: levels)
    }

    /// Always the same number of bars, so the row does not grow as the recording starts.
    private var padded: [Double] {
        let count = DebriefSession.levelCount
        let recent = Array(levels.suffix(count))
        return Array(repeating: 0, count: count - recent.count) + recent
    }
}

/// Sending this note to a lane. The button names the developer only for the built-in lane.
struct DeveloperLaneSection: View {
    let noteId: String
    let session: DebriefSession
    @AppStorage("vd.developerLane") private var link = ""
    @State private var confirming = false

    var body: some View {
        Section {
            if let lane = DeveloperLane.current(pasted: link) {
                let pasted = DeveloperLane.parse(link) != nil
                switch session.sharing(for: noteId) {
                case .sending(let done, let total):
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(total > 0 ? "Sending part \(done) of \(total)" : "Encrypting")
                    }
                case .sent(let count):
                    Label("Sent, in \(count) encrypted messages", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                default:
                    if case .failed(let why) = session.sharing(for: noteId) {
                        Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Button {
                        confirming = true
                    } label: {
                        Label(pasted ? "Send to lane \(lane.vault)" : "Send to the developer", systemImage: "paperplane")
                    }
                    .confirmationDialog("Send this note off this device?", isPresented: $confirming, titleVisibility: .visible) {
                        Button("Send the audio, transcript and debrief") {
                            Task { await session.share(noteId: noteId, lane: lane) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("It is encrypted on this device to the key \(lane.fingerprint). The server that carries it cannot read it.")
                    }
                }
            } else {
                Text("There is no lane in this build. Paste a lane link in Settings to be able to send a note.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Send")
        } footer: {
            Text("Sending is never automatic. It asks every time, and names the key the note is encrypted to.")
        }
    }
}
