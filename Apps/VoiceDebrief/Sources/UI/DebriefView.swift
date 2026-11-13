import SwiftUI
import UniformTypeIdentifiers

/// The working screen: choose the language, record or bring a voice note, read the result.
struct DebriefView: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var locales: [String] = []
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Language spoken", selection: $localeId) {
                        ForEach(locales, id: \.self) { id in
                            Text(LocaleNames.name(id)).tag(id)
                        }
                    }
                    .disabled(session.isBusy || locales.isEmpty)
                } footer: {
                    Text(locales.isEmpty
                         ? "Apple's speech model reports no languages on this device."
                         : "Apple's speech model needs to know the language before it listens. The debrief is written in the same language.")
                }

                Section {
                    controls
                } footer: {
                    Text("Transcribed and summarised on this device by Apple's models. Nothing is sent anywhere unless you choose to save a debrief to your vault or send a note to the developer. A result that is not saved is lost when the app closes.")
                }

                if let run = session.run {
                    RunSections(run: run)
                    if run.transcript != nil, !session.isBusy {
                        SaveToVaultSection(session: session, book: book)
                    }
                    if session.canShareAudio {
                        DeveloperLaneSection(session: session)
                    }
                }
            }
            .navigationTitle("VoiceDebrief")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let chosen = localeId
                    Task { await session.importFile(url, localeId: chosen) }
                }
            }
            .task { await loadLocales() }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .recording(let since):
            HStack(spacing: 12) {
                LevelBars(levels: session.levels)
                Spacer()
                Text(since, style: .timer).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording")
            if !session.liveSettled.isEmpty || !session.liveVolatile.isEmpty {
                (Text(session.liveSettled) + Text(session.liveVolatile).foregroundStyle(.secondary))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !session.liveNote.isEmpty {
                Text(session.liveNote).font(.footnote).foregroundStyle(.orange)
            } else {
                Text("Listening").font(.callout).foregroundStyle(.secondary)
            }
            Button("Stop and debrief") {
                let chosen = localeId
                Task { await session.stopRecording(localeId: chosen) }
            }
            .bold()
        case .working(let what):
            HStack(spacing: 12) {
                ProgressView()
                Text(what)
            }
        default:
            if case .failed(let why) = session.phase {
                Label(why, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Button {
                let chosen = localeId
                Task { await session.startRecording(localeId: chosen) }
            } label: {
                Label("Record a voice note", systemImage: "mic")
            }
            .disabled(localeId.isEmpty)
            Button {
                importing = true
            } label: {
                Label("Choose an audio file", systemImage: "folder")
            }
            .disabled(localeId.isEmpty)
        }
    }

    private func loadLocales() async {
        let supported = await SpeechFileTranscriber.supportedLocaleIds()
        locales = supported
        if localeId.isEmpty || !supported.contains(localeId) {
            localeId = await SpeechFileTranscriber.defaultLocaleId() ?? supported.first ?? ""
        }
    }
}

/// The result of a run: how each step went, the debrief, the transcript.
struct RunSections: View {
    let run: DebriefRun

    var body: some View {
        Section("How it went") {
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

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: "mic.fill").foregroundStyle(.red)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.red.opacity(0.35 + 0.65 * level))
                    .frame(width: 3, height: 4 + 24 * level)
            }
        }
        .frame(height: 30)
        .animation(.linear(duration: 0.08), value: levels)
    }

    /// Always the same number of bars, so the row does not grow as the recording starts.
    private var padded: [Double] {
        let count = DebriefSession.levelCount
        let recent = Array(levels.suffix(count))
        return Array(repeating: 0, count: count - recent.count) + recent
    }
}

/// Sending this note to the developer. Shown only after a run; does nothing without a lane link.
struct DeveloperLaneSection: View {
    let session: DebriefSession
    @AppStorage("vd.developerLane") private var link = ""

    var body: some View {
        Section {
            if let lane = DeveloperLane.current(pasted: link) {
                switch session.sharing {
                case .sending(let done, let total):
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(total > 0 ? "Sending part \(done) of \(total)" : "Encrypting")
                    }
                case .sent(let count):
                    Label("Sent, in \(count) encrypted messages", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                default:
                    if case .failed(let why) = session.sharing {
                        Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Button {
                        Task { await session.shareWithDeveloper(lane: lane) }
                    } label: {
                        Label("Send this note to the developer", systemImage: "paperplane")
                    }
                }
            } else {
                Text("There is no developer lane in this build. Paste a lane link on the Diagnostics tab to be able to send a note.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Help judge the models")
        } footer: {
            if let lane = DeveloperLane.current(pasted: link) {
                Text("This sends the audio, the transcript and the debrief of this note off this device, encrypted to the developer's key (\(lane.fingerprint)). The server that carries it cannot read it. Send only a note you are happy to share.")
            }
        }
    }
}
