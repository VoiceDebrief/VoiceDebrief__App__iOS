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

/// The version, at the top beside the balance, opening what changed in it (owner's request, 14 November 2026).
struct VersionBadge: View {
    var body: some View {
        Link(destination: AppInfo.notes()) {
            Text(AppInfo.shortVersion())
                .font(.caption.weight(.semibold).monospacedDigit())
                .fixedSize()
        }
        .accessibilityLabel("Version \(AppInfo.versionLine()). Opens what is new in it.")
    }
}

/// Where the work is happening now: Apple's model on this device, or the network (issue 027). The owner
/// could not tell which was in use; this says it in two plain lines, green while each is busy.
struct WhereWorkHappens: View {
    let session: DebriefSession

    static func onDevice(_ session: DebriefSession) -> String? { WhereWorkHappens(session: session).onDevice }
    static func network(_ session: DebriefSession) -> String? { WhereWorkHappens(session: session).network }

    fileprivate var onDevice: String? {
        if session.recordingNote != nil { return "Listening and writing the words as you speak" }
        if let id = session.currentNoteId, let text = session.workingText(for: id) {
            return text == "Writing the debrief" ? "Apple's model is writing the debrief" : "Apple's speech model: \(text.lowercased())"
        }
        return nil
    }

    fileprivate var network: String? {
        guard let name = session.sendingTo else { return nil }
        if case .sending(let done, let total) = session.sharing, total > 0 { return "Sending to \(name), part \(done) of \(total), encrypted" }
        return "Sending to \(name), encrypted"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("iphone", "On this device", onDevice ?? "Nothing running", busy: onDevice != nil)
            row("network", "Network", network ?? "Not in use: nothing is leaving this device", busy: network != nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(_ icon: String, _ title: String, _ detail: String, busy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(busy ? Color.green : Color.secondary)
                .symbolEffect(.pulse, isActive: busy)
                .frame(width: 22)
            Text(title).font(.footnote.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(busy ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// What happened where, while the app is open: each time the device's models or the network started
/// on something. Behind the two small icons in the bar.
@MainActor
@Observable
final class WorkLog {
    static let shared = WorkLog()
    struct Entry: Identifiable { let id = UUID(); let at: Date; let place: String; let what: String }
    private(set) var entries: [Entry] = []
    func note(_ place: String, _ what: String) {
        if entries.first?.what == what && entries.first?.place == place { return }
        entries.insert(Entry(at: Date(), place: place, what: what), at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
    }
}

/// Two small icons in the bar: this device and the network, green while each is in use, steady and in
/// the same place whatever the screen does (the owner: the panel "moves down as I speak" and "goes on and
/// off"). Tap for what each is, and what has happened.
struct WorkStatusIcons: View {
    let session: DebriefSession
    @State private var showing = false

    var body: some View {
        let device = WhereWorkHappens.onDevice(session)
        let net = WhereWorkHappens.network(session)
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "iphone").foregroundStyle(device != nil ? Color.green : Color.secondary)
                    .symbolEffect(.pulse, isActive: device != nil)
                Image(systemName: "network").foregroundStyle(net != nil ? Color.green : Color.secondary)
                    .symbolEffect(.pulse, isActive: net != nil)
            }
            .font(.footnote)
        }
        .accessibilityLabel("Where the work happens: this device \(device ?? "idle"), network \(net ?? "not in use")")
        .onChange(of: device) { _, value in if let value { WorkLog.shared.note("This device", value) } }
        .onChange(of: net) { _, value in if let value { WorkLog.shared.note("Network", value) } }
        .sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    Section {
                        Label { Text("This device: \(device ?? "nothing running")") } icon: { Image(systemName: "iphone") }
                        Label { Text("Network: \(net ?? "not in use, nothing is leaving this device")") } icon: { Image(systemName: "network") }
                    } footer: {
                        Text("Green while in use. On this device: Apple's speech and language models, which never send your words anywhere. Network: only a note you send, encrypted, or a vault you push or pull.")
                    }
                    Section("What has happened") {
                        if WorkLog.shared.entries.isEmpty { Text("Nothing yet since the app opened.").foregroundStyle(.secondary) }
                        ForEach(WorkLog.shared.entries) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.what)
                                Text("\(e.place) · \(e.at.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Where the work happens")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
            }
        }
    }
}
