import SwiftUI

/// What a note holds: the debrief, the transcript, sharing, and how each step went.
struct RunSections: View {
    let run: DebriefRun
    /// True when the note's heading already shows "In one sentence", so it is not repeated at the end.
    var oneSentenceShown = false
    /// Called with a line's start when it is tapped, to play the recording from there.
    var onLine: ((Int) -> Void)? = nil

    /// The debrief's blocks, without the one sentence when the heading shows it.
    private func blocks(_ debrief: String) -> [DebriefBlock] {
        let all = DebriefMarkdown.blocks(debrief)
        guard oneSentenceShown else { return all }
        var out: [DebriefBlock] = []
        var skipping = false
        for block in all {
            if case .heading(let text) = block { skipping = text.lowercased().hasSuffix("in one sentence") }
            if !skipping { out.append(block) }
        }
        return out
    }

    var body: some View {
        if let debrief = run.debrief {
            Section {
                ForEach(Array(blocks(debrief).enumerated()), id: \.offset) { _, block in
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
                            .foregroundStyle(onLine == nil ? Color.secondary : Color.accentColor)
                        Text(line.text)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onLine?(line.startMs) }
                    .accessibilityAddTraits(onLine == nil ? [] : .isButton)
                    .accessibilityHint(onLine == nil ? "" : "Plays the recording from here")
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

    /// "English" for "en-GB": short enough for a toolbar.
    static func language(_ id: String) -> String {
        let code = Locale(identifier: id).language.languageCode?.identifier ?? id
        return Locale.current.localizedString(forLanguageCode: code) ?? id
    }
}

extension View {
    /// Holds a list to a readable width on a wide screen and centres it, so that an iPad in landscape
    /// is not a stretched phone (review round 1, issue 035). No effect on an iPhone.
    func readableWidth(_ width: CGFloat = 720) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
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


/// A note's recording: play and pause, where it is, its length and size. Shown on every note that
/// has audio, including one that was interrupted, so that "kept" can be heard (issue 029).
struct PlayerSection: View {
    let url: URL
    let player: NotePlayer

    private var size: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(player.duration == 0)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play the recording")
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 0.1))
                        .disabled(player.duration == 0)
                    Text("\(Timecode.format(ms: Int(player.position * 1000))) of \(Timecode.format(ms: Int(player.duration * 1000))) · \(size)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ShareLink(item: url, preview: SharePreview("Voice note recording")) {
                Label("Share or save the recording", systemImage: "square.and.arrow.up")
            }
            if let problem = player.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Recording")
        } footer: {
            Text("Tap a line of the transcript to hear it. Sharing lets you save the audio to Files or send it anywhere; it leaves this device unencrypted.")
        }
        .onAppear { player.load(url) }
        .onChange(of: url) { _, new in player.load(new) }
    }
}
