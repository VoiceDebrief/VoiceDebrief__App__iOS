import SwiftUI
import UniformTypeIdentifiers

/// The working screen: choose the language, record or bring a voice note, read the result.
struct DebriefView: View {
    let session: DebriefSession
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
                    Text("Transcribed and summarised on this device by Apple's models. Nothing is sent anywhere, and in this build nothing is saved: closing the app loses the result.")
                }

                if let run = session.run {
                    RunSections(run: run)
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
            HStack {
                Image(systemName: "waveform").foregroundStyle(.red)
                Text("Recording")
                Spacer()
                Text(since, style: .timer).monospacedDigit().foregroundStyle(.secondary)
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
                Task { await session.startRecording() }
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
