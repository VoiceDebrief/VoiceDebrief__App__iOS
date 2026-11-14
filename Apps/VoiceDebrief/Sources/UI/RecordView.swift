import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Home: one large control to record, the words as they are spoken, and the most recent notes.
/// Stopping saves the note and opens it at once; the transcript and debrief fill in there.
struct RecordView: View {
    let session: DebriefSession
    let book: VaultBook
    /// Opens another part of the app, for the tiles below the recording.
    var go: (RootTab) -> Void = { _ in }
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
    /// Who the next recording is for: a recipient's link, or empty for "just me" (the owner's
    /// contact-driven flow, 14 November 2026). Remembered, so sending to the usual person is one tap.
    @AppStorage("vd.addressee") private var addressee = ""
    /// True while the Talk to Claude button owns the recording, so this screen leaves it alone.
    @AppStorage("vd.talking") private var talking = false

    private var addresseeRecipient: Recipient? {
        addressee.isEmpty ? nil : RecipientStore.shared.all.first { $0.link == addressee }
    }
    @State private var queuedNoteId: String?
    /// What is new since the app was last opened, worked out once when the screen first appears (issue 025).
    @State private var briefing: Briefing?
    @AppStorage("vd.lastOpened") private var lastOpened: Double = 0
    @AppStorage("vd.lastVersion") private var lastVersion = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // At the top when idle; while recording it is pinned above the growing words.
                        if !isRecording { controls }
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
            .safeAreaInset(edge: .top) {
                if isRecording { controls.background(.bar) }
            }
            .navigationTitle("VoiceDebrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CreditCounter() }
                ToolbarItem(placement: .topBarLeading) { VersionBadge() }
                if !isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        LanguageMenu()
                            .disabled(session.isBusy)
                    }
                }
                // Throwing a recording away is kept far from the thumb and takes two presses.
                if isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
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
            .onChange(of: session.finishRequests) { _, _ in
                // A spoken "send this now", or a headphone or car button, finishes like the tick.
                if isRecording, !talking { Task { await toggle() } }
            }
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
                Text("Saved to this device as you speak. To finish without a tap, say \"send this now\", or press play/pause on your headphones.")
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
                    ForEach(Array(briefing.lines.prefix(3)), id: \.self) { line in
                        Text(line).font(.callout)
                    }
                    Button("Dismiss") { self.briefing = nil }
                }
            }
            if let name = queuedFor, let id = queuedNoteId {
                SendProgressCard(noteId: id, to: name, session: session) {
                    withAnimation { queuedFor = nil; queuedNoteId = nil }
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
            explore
        }
    }

    /// Every other part of the app, one tile each, so that a person can find and try it.
    private var explore: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                tile("Library", "Every note, by day", "tray.full", .library)
                tile("Contacts", "Who notes go to; add by QR", "person.2", .contacts)
                tile("Vaults", "Encrypted, yours, on every device", "lock.shield", .vaults)
                tile("Identity", "Your keys and your devices", "person.badge.key", .identity)
                tile("Credit", "What each thing costs", "sterlingsign.circle", .credit)
                tile("Lab", "Try Apple's model, tools on and off", "flask", .lab)
                tile("Your words", "Names the clean text should know", "character.book.closed", .words)
                tile("Your activity", "What you have used; send it", "chart.bar", .activity)
                tile("What this build does", "Built, in test, not built", "checklist", .about)
            }
            Link(destination: AppInfo.notes()) {
                Label("What is new in \(AppInfo.shortVersion())", systemImage: "sparkles")
                    .font(.callout)
            }
        }
        .padding(.top, 8)
    }

    private func tile(_ title: String, _ line: String, _ icon: String, _ to: RootTab) -> some View {
        Button { UsageLog.shared.action("home.tile.\(to.rawValue)"); go(to) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(line).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private var addresseeChips: some View {
        ViewThatFits(in: .horizontal) {
            chipRow
            ScrollView(.horizontal, showsIndicators: false) { chipRow.padding(.horizontal, 16) }
        }
        .frame(maxWidth: .infinity)
    }

    private var chipRow: some View {
            HStack(spacing: 8) {
                chip("Just me", systemImage: "person", selected: addresseeRecipient == nil) { addressee = "" }
                ForEach(RecipientStore.shared.all) { recipient in
                    chip(recipient.name, systemImage: "paperplane", selected: addressee == recipient.link) { addressee = recipient.link }
                }
                NavigationLink {
                    RecipientsView()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }
    }

    private func chip(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark" : systemImage)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if !isRecording {
                Text("Record a voice note")
                    .font(.title2.weight(.semibold))
                Text("Record a note for")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addresseeChips
            } else if let to = addresseeRecipient {
                Label("For \(to.name): sent when you finish", systemImage: "paperplane.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Button {
                Task { await toggle() }
            } label: {
                ZStack {
                    Circle()
                        .fill(localeId.isEmpty ? Color.gray : Color.green)
                        .frame(width: 120, height: 120)
                        .shadow(color: .green.opacity(0.35), radius: 12, y: 4)
                    Image(systemName: isRecording ? "checkmark" : "mic.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // Live whatever the pipeline is doing: a thought that arrives while the last note is being
            // written up is recorded, and waits its turn (issue 030).
            .disabled(localeId.isEmpty)
            .accessibilityLabel(isRecording ? (addresseeRecipient.map { "Finish and send to \($0.name)" } ?? "Finish and debrief") : "Record")

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Finish and send in one press, then stay here to record the next (issue 026). Only the
            // person's own recipients: the developer of the test build always asks first.
            if isRecording, !RecipientStore.shared.added.filter({ $0.link != addressee }).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RecipientStore.shared.added.filter { $0.link != addressee }) { recipient in
                            Button {
                                Task {
                                    if let id = await session.stopRecording() {
                                        session.send(noteId: id, to: recipient)
                                        queuedFor = recipient.name
                                        queuedNoteId = id
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var caption: String {
        if isRecording {
            if let to = addresseeRecipient { return "Tap to finish: kept, written up, and sent to \(to.name)" }
            return "Tap to finish: the note is kept, then transcribed and debriefed"
        }
        if session.isProcessing {
            let more = session.waiting.isEmpty ? "" : ", \(session.waiting.count) more waiting"
            return "Tap to record. The last note is being written up\(more)."
        }
        if let to = addresseeRecipient { return "Tap to record for \(to.name). It is saved as you speak and sent when you finish." }
        return "Tap to record. It is saved as you speak."
    }

    private func toggle() async {
        if isRecording {
            UsageLog.shared.action("record.finish")
            if let id = await session.stopRecording() {
                if let to = addresseeRecipient {
                    // Chosen before recording, so finishing is the send: no second question.
                    session.send(noteId: id, to: to)
                    queuedFor = to.name
                    queuedNoteId = id
                } else {
                    path.append(id)
                }
            }
        } else {
            UsageLog.shared.action(addresseeRecipient == nil ? "record.start" : "record.start.for-contact")
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
        if working == nil {
            if note.sendProblem != nil, let to = note.pendingSend?.name { parts.append("Not sent to \(to)") }
            else if let to = note.pendingSend?.name { parts.append("Waiting to send to \(to)") }
            else if let sent = note.sends?.last { parts.append("Sent to \(sent.to) \(sent.at.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))") }
        }
        return parts.joined(separator: " · ")
    }
}
