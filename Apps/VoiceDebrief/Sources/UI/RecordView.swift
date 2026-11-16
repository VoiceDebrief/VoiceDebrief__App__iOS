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
    @State private var showingMessages = false
    @State private var tuning = false
    // The record screen's look, tuned by the owner on the screen itself (15 November 2026: "a settings button
    // on this page: the sensitivity of the bars, the colour of the green button, the height of the wave").
    @AppStorage("vd.tune.sensitivity") private var sensitivity = 0.7
    @AppStorage("vd.tune.barHeight") private var barHeight = 32.0
    @AppStorage("vd.tune.buttonColour") private var buttonColour = "green"
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The big button's colour, as tuned.
    private var tunedColour: Color {
        switch buttonColour {
        case "blue": .blue
        case "orange": .orange
        case "purple": .purple
        case "teal": .teal
        default: DS.Palette.green
        }
    }

    /// The tune panel: changes apply as you move them, also while recording.
    private var tunePanel: some View {
        NavigationStack {
            Form {
                Section("Level bars") {
                    LabeledContent("Sensitivity") { Slider(value: $sensitivity, in: 0.3...1.5) }
                    LabeledContent("Height") { Slider(value: $barHeight, in: 16...80) }
                    LevelBars(levels: (0..<DebriefSession.levelCount).map { i in pow(0.5 + 0.5 * sin(Double(i) / 3), 1 / max(sensitivity, 0.2)) },
                              height: barHeight, barWidth: 4)
                }
                Section("The record button") {
                    Picker("Colour", selection: $buttonColour) {
                        ForEach(["green", "blue", "teal", "orange", "purple"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Back to how it was") { sensitivity = 0.7; barHeight = 32; buttonColour = "green" }
                }
            }
            .navigationTitle("Tune this screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { tuning = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// iPad and Mac at full width: the two-column record screen.
    private var wide: Bool { sizeClass == .regular }
    /// A picture added while recording (pasted or chosen) and a line, sent with the note when it goes.
    @State private var attached: UIImage?
    /// The attached picture shown full size (the owner: "click on the little screenshot and see a preview").
    @State private var previewingPicture = false
    @State private var attachedLine = ""
    @State private var attachSender = PictureSender()
    @State private var clipboardHasPicture = false
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

    /// The chosen recipient as a face for the route strip; Claude (developer) is drawn as the conductor.
    private var routeTo: [AvatarSubject] {
        guard let to = addresseeRecipient else { return [] }
        return [AvatarSubject(recipient: to)]
    }

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
                Group {
                    if wide {
                        // iPad and Mac: what you do on the left, what came back on the right (the owner:
                        // "on the iPad or laptop we can do better"). The control stays in the left column.
                        RecordWideLayout {
                            // While recording, the time first and then the control ("Recording 1:30" sat
                            // below the Finish button, seen in the screens session's pictures). Pinned, so
                            // the growing words scroll under them and the button never leaves the screen.
                            recordingHeader
                            controls
                        } left: {
                            content
                            Color.clear.frame(height: 1).id(Self.bottomId)
                        } right: {
                            // Tabs: the live conversation, Claude's updates, the agents, and your notes.
                            RecordSidePane(session: session, book: book) {
                                recent
                                explore
                            }
                        }
                    } else {
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
                    }
                }
                .onChange(of: session.liveSettled.count + session.liveVolatile.count) { _, _ in
                    guard isRecording else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .top) {
                if isRecording && !wide { controls.background(.bar) }
            }
            .navigationTitle("VoiceDebrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CreditCounter() }
                ToolbarItem(placement: .topBarLeading) { VersionBadge() }
                ToolbarItem(placement: .topBarTrailing) { WorkStatusIcons(session: session) }
                if !isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Claude's replies to what you sent (the owner: "see what was acted on").
                        Button { showingMessages = true } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .overlay(alignment: .topTrailing) {
                                    if !(AgentsDesk.shared.report?.messages ?? []).filter({ $0.from != "you" }).isEmpty {
                                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: 3, y: -3)
                                    }
                                }
                        }
                        .accessibilityLabel("Messages to and from Claude")
                    }
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
            // The shared vault's report says whether a newer build is waiting, and carries Claude's replies.
            .task { await AgentsDesk.shared.refresh(book: book) }
            .sheet(isPresented: $tuning) { tunePanel }
            .sheet(isPresented: $showingMessages) {
                NavigationStack { MessagesToClaudeView(session: session, book: book) }
                    .presentationSizing(.page)
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

    /// "Recording", the time and where it is kept.
    @ViewBuilder private var recordingHeader: some View {
        if case .recording(let since) = session.phase {
            VStack(spacing: 6) {
                Label("Recording", systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(since, style: .timer)
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                Text("Saved to this device as you speak.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .recording = session.phase {
            // On iPad and Mac the header sits above the control instead (see the wide layout).
            if !wide { recordingHeader }
            liveCard
            attachCard
        } else {
            if session.store.notes.isEmpty {
                // The first visit: below the control, what happens, in a picture and one line.
                SectionHero(tab: .record, title: "Your first voice note",
                            line: "Saved as you speak, then transcribed and debriefed on this device.",
                            height: 210, image: "VDArt-hero")
            }

            if case .failed(let why) = session.phase {
                card {
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Dismiss") { session.clearFailure() }
                }
            }
            if let latest = AgentsDesk.shared.report?.latestBuild, AppInfo.isNewer(latest, than: AppInfo.version()) {
                card {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("v\(latest) is in TestFlight").font(.headline)
                            Text("You have v\(AppInfo.version()). Open TestFlight to update.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link("Open", destination: AppInfo.testFlight).buttonStyle(.borderedProminent)
                    }
                }
            }
            if let briefing, !briefing.isEmpty {
                card {
                    if let version = briefing.upgradedTo {
                        if let history = VersionHistory.bundled() {
                            NavigationLink {
                                WhatsNewView(history: history)
                            } label: {
                                Label("Updated to \(version): see what is new", systemImage: "sparkles")
                                    .font(.callout.weight(.semibold))
                            }
                        } else {
                            Link(destination: AppInfo.notes(for: version)) {
                                Label("Updated to \(version): see what is new", systemImage: "sparkles")
                                    .font(.callout.weight(.semibold))
                            }
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
            if !wide {
                recent
                explore
            }
        }
    }

    /// Every other part of the app, one illustrated tile each, so that a person can find and try it.
    /// Titles, symbols, colours and pictures come from `RootTab` (Sources/UI/Design/Sections.swift).
    private var explore: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(title: "Explore", symbol: "square.grid.2x2.fill",
                            subtitle: "Everything else the app can do. Each tile opens it.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Space.s)], spacing: DS.Space.s) {
                ForEach(RootTab.allCases.filter { $0 != .record }) { tab in
                    Button {
                        UsageLog.shared.action("home.tile.\(tab.rawValue)")
                        go(tab)
                    } label: {
                        SectionTile(tab: tab)
                    }
                    .buttonStyle(.plain)
                }
            }
            Link(destination: AppInfo.notes()) {
                Label("What is new in \(AppInfo.shortVersion())", systemImage: Icon.whatsNew)
                    .font(.callout)
            }
        }
        .padding(.top, DS.Space.xs)
    }

    /// While recording: add a picture and a line that go with the note (the owner: "I just took a screenshot
    /// of this; where do I put it? Detect copy and paste here"). A picture on the clipboard is offered at
    /// once, without reading it until you tap.
    private var attachCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                if let attached {
                    HStack(spacing: 10) {
                        Button { previewingPicture = true } label: {
                            Image(uiImage: attached).resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show the picture full size")
                        .fullScreenCover(isPresented: $previewingPicture) { PicturePreview(image: attached) }
                        Text(addresseeRecipient.map { "Goes with the note to \($0.name)" } ?? "Kept with nothing: choose who the note is for to send it")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove", role: .destructive) { self.attached = nil }.font(.footnote)
                    }
                } else if clipboardHasPicture {
                    Button {
                        if let image = UIPasteboard.general.image { attached = image }
                        clipboardHasPicture = false
                    } label: {
                        Label("A picture is on the clipboard: add it to this note", systemImage: "doc.on.clipboard.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }
                TextField("Add a line (optional)", text: $attachedLine, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 10) {
                    Button {
                        if let image = UIPasteboard.general.image { attached = image }
                    } label: { Label("Paste picture", systemImage: "doc.on.clipboard") }
                    PhotoChooser { attached = $0 }
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
        }
        .onAppear { clipboardHasPicture = UIPasteboard.general.hasImages }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasPicture = UIPasteboard.general.hasImages
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            clipboardHasPicture = UIPasteboard.general.hasImages
        }
    }

    private var liveCard: some View {
        card {
            if session.microphoneSilent {
                Label("No sound is reaching the microphone. Another app (a call, FaceTime, Siri, the car) may be using it, or the microphone is covered.",
                      systemImage: "mic.slash.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                .dsSurface()
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
        .dsSurface()
    }

    // MARK: The control, pinned where a thumb reaches

    private var addresseeChips: some View {
        Group {
            if wide {
                // In the iPad and Mac column the chips wrap onto more lines rather than run off the edge
                // ("Maria (in" was cut, seen in the screens session's pictures).
                ChipFlow(spacing: 8) { chipItems }
            } else {
                ViewThatFits(in: .horizontal) {
                    chipRow
                    ScrollView(.horizontal, showsIndicators: false) { chipRow.padding(.horizontal, 16) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var chipRow: some View {
        HStack(spacing: 8) { chipItems }
    }

    @ViewBuilder private var chipItems: some View {
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
                // Who it is from and who it goes to, at a glance (the owner: "me on the left, an arrow, who
                // I'm sending it to").
                SendRoute(from: MyLook.shared.subject(id: "me"), to: routeTo, size: 44)
                    .padding(.vertical, 4)
                Text("Record a note for")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addresseeChips
                PictureButtons(recipient: addresseeRecipient)
            } else {
                if let to = addresseeRecipient {
                    Label("For \(to.name): sent when you finish", systemImage: "paperplane.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                LevelBars(levels: session.levels.map { pow($0, 1 / max(sensitivity, 0.2)) }, height: barHeight, barWidth: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone level")
                // A small counter: that it is still recording and still hearing words (the owner).
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 10) {
                        if session.paused { Label("Paused", systemImage: "pause.fill").foregroundStyle(.orange) }
                        Text(Timecode.duration(seconds: session.recordedSeconds)).monospacedDigit()
                        Text("·")
                        Text("\(session.wordsHeard) words").monospacedDigit()
                        Button { tuning = true } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Tune this screen")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 24) {
            if isRecording {
                // Pause and carry on, in the same note (the owner: "a pause button and the finish button").
                Button {
                    Task { if session.paused { await session.resumeRecording() } else { await session.pauseRecording() } }
                } label: {
                    Image(systemName: session.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.orange, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.paused ? "Carry on recording" : "Pause")
            }
            Button {
                Task { await toggle() }
            } label: {
                ZStack {
                    Circle()
                        .fill(localeId.isEmpty ? AnyShapeStyle(Color.gray) : AnyShapeStyle(tunedColour.gradient))
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(tunedColour.opacity(isRecording ? 0.5 : 0.18), lineWidth: 8)
                        .frame(width: 140, height: 140)
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
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isRecording {
                // The words that act, in plain sight (the owner: "if I had a list of the keywords").
                Text("Say \"send this now\" or \"stop recording\" at the end, then pause. Headphone play/pause also finishes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
                    let image = attached, line = attachedLine
                    if image != nil || !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let image, let jpeg = PictureSender.jpeg(image) { session.store.keepPicture(jpeg, for: id) }
                        Task { await attachSender.send(image: image, caption: line, to: to, about: id) }
                    }
                    attached = nil; attachedLine = ""
                    queuedFor = to.name
                    queuedNoteId = id
                } else {
                    attached = nil; attachedLine = ""
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
                // At most one mark, in words and its colour (the design; Model/NoteMark.swift).
                NoteMarkPill(mark: NoteMark.of(note, working: working))
            }
            Spacer(minLength: 8)
            if working != nil {
                ProgressView()
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
        // What is working, and a failed send, are said by the mark below; the rest is said here.
        if working == nil, note.stateLine != "On this device" { parts.append(note.stateLine) }
        if working == nil, note.sendProblem == nil {
            if let to = note.pendingSend?.name { parts.append("Waiting to send to \(to)") }
            else if let sent = note.sends?.last { parts.append("Sent to \(sent.to) \(sent.at.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)))") }
        }
        return parts.joined(separator: " · ")
    }
}


/// Chips laid out left to right, wrapping onto a new line when the row is full, each line centred.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let gap: CGFloat = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
