import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Home: one large control to record, the words as they are spoken, and the most recent notes.
/// Stopping saves the note and opens it at once; the transcript and debrief fill in there.
struct RecordView: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var importing = false
    @State private var path: [String] = []

    private var isRecording: Bool {
        if case .recording = session.phase { return true }
        return false
    }

    private static let bottomId = "record-bottom"

    private var isWorking: Bool {
        if case .working = session.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        content
                        // The live words grow downwards: this is what the screen follows while recording.
                        Color.clear.frame(height: 1).id(Self.bottomId)
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: session.liveSettled.count + session.liveVolatile.count) { _, _ in
                    guard isRecording else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("VoiceDebrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CreditCounter() }
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageMenu()
                        .disabled(session.isBusy)
                }
            }
            .navigationDestination(for: String.self) { id in
                NoteDetailView(noteId: id, session: session, book: book)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let chosen = localeId
                    Task { @MainActor in
                        if let id = session.importFile(url, localeId: chosen) { path.append(id) }
                    }
                }
            }
            .onChange(of: isRecording) { _, recording in
                // Keep the screen awake while recording: the recording stops if the app leaves the front.
                Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = recording }
            }
            .sensoryFeedback(.impact, trigger: isRecording)
        }
    }

    // MARK: The middle of the screen

    @ViewBuilder
    private var content: some View {
        if case .recording(let since) = session.phase {
            VStack(spacing: 6) {
                Label("Recording", systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(since, style: .timer)
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                Text("Saved to this device as you speak. If the recording is cut short, what was said is kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            LevelBars(levels: session.levels, height: 72, barWidth: 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Microphone level")
            liveCard
        } else {
            VStack(spacing: 6) {
                Text("Record a voice note")
                    .font(.title2.weight(.semibold))
                Text("Transcript and debrief, made on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 8)

            if case .failed(let why) = session.phase {
                card {
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Dismiss") { session.clearFailure() }
                }
            }
            if let notice = session.notice {
                card {
                    Label(notice, systemImage: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button("Dismiss") { session.clearNotice() }
                }
            }
            if localeId.isEmpty {
                card {
                    Label("Apple's speech model reports no language on this device, so there is nothing to transcribe with.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            recent
        }
    }

    private var liveCard: some View {
        card {
            if !session.liveSettled.isEmpty || !session.liveVolatile.isEmpty {
                (Text(session.liveSettled) + Text(session.liveVolatile).foregroundStyle(.secondary))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !session.liveNote.isEmpty {
                Text(session.liveNote).font(.footnote).foregroundStyle(.orange)
            } else {
                Text("Listening").font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live transcript")
    }

    @ViewBuilder
    private var recent: some View {
        let notes = Array(session.store.notes.prefix(3))
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent")
                    .font(.headline)
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(notes) { note in
                        NavigationLink(value: note.id) {
                            NoteRow(note: note, working: session.workingText(for: note.id))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if note.id != notes.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: The control, pinned where a thumb reaches

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                Task { await toggle() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isWorking || localeId.isEmpty ? Color.gray : Color.red)
                        .frame(width: 88, height: 88)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking || localeId.isEmpty)
            .accessibilityLabel(isRecording ? "Stop and debrief" : "Record")

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !isRecording {
                Button {
                    importing = true
                } label: {
                    Label("Choose an audio file", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(isWorking || localeId.isEmpty)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var caption: String {
        if isRecording { return "Tap to stop and debrief" }
        if case .working(let what) = session.phase { return "Finishing the last note: \(what)" }
        return "Tap to record"
    }

    private func toggle() async {
        if isRecording {
            if let id = await session.stopRecording() {
                path.append(id)
            }
        } else {
            await session.startRecording(localeId: localeId)
        }
    }
}

/// The language Apple's speech model is told to listen for. It has to be chosen before recording.
struct LanguageMenu: View {
    @AppStorage("vd.localeId") private var localeId = ""
    @State private var locales: [String] = []

    var body: some View {
        Menu {
            Picker("Language spoken", selection: $localeId) {
                ForEach(locales, id: \.self) { id in
                    Text(LocaleNames.name(id)).tag(id)
                }
            }
        } label: {
            Label(localeId.isEmpty ? "Language" : localeId, systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.medium))
        }
        .accessibilityLabel("Language spoken: \(localeId.isEmpty ? "none" : LocaleNames.name(localeId))")
        .task {
            let supported = await SpeechFileTranscriber.supportedLocaleIds()
            locales = supported
            if localeId.isEmpty || !supported.contains(localeId) {
                localeId = await SpeechFileTranscriber.defaultLocaleId() ?? supported.first ?? ""
            }
        }
    }
}

/// A note in a list: what it says, when, how long, and its state in words.
struct NoteRow: View {
    let note: Note
    var working: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.body)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if working != nil {
                ProgressView()
            } else if note.processing || note.run.transcript == nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(note.stateLine)
            }
        }
    }

    private var subtitle: String {
        var parts = [note.createdAt.formatted(date: .omitted, time: .shortened)]
        if let seconds = note.run.audioSeconds { parts.append(Timecode.duration(seconds: seconds)) }
        if let working { parts.append(working) } else if note.stateLine != "On this device" { parts.append(note.stateLine) }
        return parts.joined(separator: " · ")
    }
}
