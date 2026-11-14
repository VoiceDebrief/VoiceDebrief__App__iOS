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
    @State private var confirmingDiscard = false
    /// The recipient the last note was finished and sent to with one press, to say so on this screen.
    @State private var queuedFor: String?
    /// What is new since the app was last opened, worked out once when the screen first appears (issue 025).
    @State private var briefing: Briefing?
    @AppStorage("vd.lastOpened") private var lastOpened: Double = 0
    @AppStorage("vd.lastVersion") private var lastVersion = ""

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
                ToolbarItem(placement: .topBarLeading) { VersionBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageMenu()
                        .disabled(session.isBusy)
                }
                // Throwing a recording away is kept far from the thumb and takes two presses.
                if isRecording {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Discard", role: .destructive) { confirmingDiscard = true }
                            .font(.footnote)
                            .alert("Throw this recording away?", isPresented: $confirmingDiscard) {
                                Button("Throw it away", role: .destructive) {
                                    Task { await session.discardRecording() }
                                }
                                Button("Keep recording", role: .cancel) {}
                            } message: {
                                Text("What you have said so far will be deleted from this device. It cannot be brought back.")
                            }
                    }
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
            .task {
                // Once per launch: what changed since the last time, then remember this time.
                guard briefing == nil else { return }
                let version = AppInfo.shortVersion()
                briefing = Briefing.make(notes: session.store.notes,
                                         since: lastOpened > 0 ? Date(timeIntervalSince1970: lastOpened) : nil,
                                         lastVersion: lastVersion.isEmpty ? nil : lastVersion,
                                         version: version)
                lastOpened = Date().timeIntervalSince1970
                lastVersion = version
            }
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
            WhereWorkHappens(session: session)
        } else {
            VStack(spacing: 6) {
                Text("Record a voice note")
                    .font(.title2.weight(.semibold))
                Text("Saved as you speak, then transcribed and debriefed on this device.")
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
            if let briefing, !briefing.isEmpty {
                card {
                    if let version = briefing.upgradedTo {
                        Link(destination: AppInfo.notes(for: version)) {
                            Label("Updated to \(version): see what is new", systemImage: "sparkles")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    ForEach(briefing.lines, id: \.self) { line in
                        Text(line).font(.callout)
                    }
                    Button("Dismiss") { self.briefing = nil }
                }
            }
            if let name = queuedFor {
                card {
                    Label("Your last note will be sent to \(name) as soon as it is written up. You can record the next one now.", systemImage: "paperplane.fill")
                        .font(.callout)
                    Button("Dismiss") { queuedFor = nil }
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
            WhereWorkHappens(session: session)
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
                            NoteRow(note: note, working: session.workingText(for: note.id), showsDay: true)
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
                        .fill(localeId.isEmpty ? Color.gray : Color.green)
                        .frame(width: 88, height: 88)
                    Image(systemName: isRecording ? "checkmark" : "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // Live whatever the pipeline is doing: a thought that arrives while the last note is being
            // written up is recorded, and waits its turn (issue 030).
            .disabled(localeId.isEmpty)
            .accessibilityLabel(isRecording ? "Finish and debrief" : "Record")

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Finish and send in one press, then stay here to record the next (issue 026). Only the
            // person's own recipients: the developer of the test build always asks first.
            if isRecording, !RecipientStore.shared.added.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RecipientStore.shared.added) { recipient in
                            Button {
                                Task {
                                    if let id = await session.stopRecording() {
                                        session.send(noteId: id, to: recipient)
                                        queuedFor = recipient.name
                                    }
                                }
                            } label: {
                                Label("Finish and send to \(recipient.name)", systemImage: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if !isRecording {
                Button {
                    importing = true
                } label: {
                    Label("Choose an audio file", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(localeId.isEmpty)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var caption: String {
        if isRecording { return "Tap to finish: the note is kept, then transcribed and debriefed" }
        if session.isProcessing {
            let more = session.waiting.isEmpty ? "" : ", \(session.waiting.count) more waiting"
            return "Tap to record. The last note is being written up\(more)."
        }
        return "Tap to record. It is saved as you speak."
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
            Label(localeId.isEmpty ? "Language" : LocaleNames.language(localeId), systemImage: "globe")
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
    /// True where notes from different days sit together (Recent), so the day is said.
    var showsDay = false

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
        let time = note.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits))
        var day = ""
        if showsDay, !Calendar.current.isDateInToday(note.createdAt) {
            day = Calendar.current.isDateInYesterday(note.createdAt)
                ? "Yesterday "
                : note.createdAt.formatted(.dateTime.day().month(.abbreviated)) + " "
        }
        var parts = [day + time]
        if let seconds = note.run.audioSeconds { parts.append(Timecode.duration(seconds: seconds)) }
        if let working { parts.append(working) } else if note.stateLine != "On this device" { parts.append(note.stateLine) }
        if working == nil, let sent = note.sends?.last { parts.append("Sent to \(sent.to)") }
        return parts.joined(separator: " · ")
    }
}
