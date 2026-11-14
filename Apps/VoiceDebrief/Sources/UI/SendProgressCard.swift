import SwiftUI

/// After a note is finished for someone: where it is on its way, step by step, with what goes, until it
/// has gone (the owner, 14 November 2026: "I had no visual clue if the message was actually sent").
/// Nothing to press: it clears itself a few seconds after the note has gone. "Do not send" is there only
/// until sending starts.
struct SendProgressCard: View {
    let noteId: String
    let to: String
    let session: DebriefSession
    let onDone: () -> Void
    @State private var clearing = false

    private var note: Note? { session.store.note(noteId) }
    private var writingUp: Bool { session.workingText(for: noteId) != nil || (note?.processing ?? false) }
    private var sendingPart: (Int, Int)? {
        if case .sending(let done, let total) = session.sharing(for: noteId) { return (done, total) }
        return nil
    }
    private var sentAt: Date? { note?.sends?.last(where: { $0.to == to })?.at }
    private var failed: String? { note?.sendProblem }
    private var retrying: (attempt: Int, of: Int, next: Date)? {
        if case .retrying(let attempt, let of, let next, _) = session.sharing(for: noteId) { return (attempt, of, next) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(sentAt != nil ? "Sent to \(to)" : "Sending to \(to)").font(.headline)
                Spacer()
                if sentAt == nil, sendingPart == nil, failed == nil, retrying == nil {
                    Button("Do not send", role: .destructive) {
                        session.cancelQueuedSend(noteId)
                        onDone()
                    }
                    .font(.footnote)
                }
            }
            step("Recorded", "waveform", state: .done)
            step(writingUp ? (session.workingText(for: noteId) ?? "Writing up") : "Written up", "text.quote",
                 state: writingUp ? .active : .done)
            step(sendLabel, "lock.fill",
                 state: failed != nil && retrying == nil ? .failed : sentAt != nil ? .done : sendingPart != nil ? .active
                     : retrying != nil ? .failed : .waiting)
            if let materials { Text(materials).font(.caption).foregroundStyle(.secondary) }
            if let retrying {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    Text("No connection. Trying again \(Text(retrying.next, style: .relative)) (try \(retrying.attempt) of \(retrying.of)), or as soon as the signal is back.")
                        .font(.footnote)
                }
                Button("Try now") { session.tryAgainNow(noteId) }.buttonStyle(.bordered)
            } else if let failed {
                Text("Not sent: \(failed). It goes again when the signal is back or the app next opens.")
                    .font(.footnote).foregroundStyle(.red)
                Button("Send again") { session.tryAgainNow(noteId) }.buttonStyle(.borderedProminent)
            }
            if let sentAt {
                // Unmissable once it has gone (the owner: "way more visible that it has been sent").
                Label("Sent to \(to) at \(sentAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: writingUp)
        .animation(.snappy, value: sentAt)
        .sensoryFeedback(.success, trigger: sentAt)
        .onChange(of: sentAt) { _, sent in
            guard sent != nil, !clearing else { return }
            clearing = true
            Task { try? await Task.sleep(for: .seconds(10)); onDone() }
        }
    }

    private var sendLabel: String {
        if let sentAt { return "Encrypted and sent, \(sentAt.formatted(date: .omitted, time: .shortened))" }
        if let (done, total) = sendingPart, total > 0 { return "Encrypting and sending, part \(done) of \(total)" }
        if sendingPart != nil { return "Encrypting" }
        return "Encrypted and sent when written up"
    }

    /// What goes: the audio, the transcript and the debrief, as far as they exist yet.
    private var materials: String? {
        guard let note else { return nil }
        var parts: [String] = []
        if let seconds = note.run.audioSeconds { parts.append("audio \(Timecode.duration(seconds: seconds))") }
        if let lines = note.run.transcript?.lines.count, lines > 0 { parts.append("transcript, \(lines) line\(lines == 1 ? "" : "s")") }
        if note.run.debrief != nil { parts.append("debrief") }
        return parts.isEmpty ? nil : "Goes: " + parts.joined(separator: " · ")
    }

    private enum StepState { case waiting, active, done, failed }

    private func step(_ title: String, _ icon: String, state: StepState) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color(state).opacity(0.15)).frame(width: 28, height: 28)
                switch state {
                case .active: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(color(state))
                        .transition(.scale.combined(with: .opacity))
                case .failed: Image(systemName: "exclamationmark").font(.caption.weight(.bold)).foregroundStyle(color(state))
                case .waiting: Image(systemName: icon).font(.caption).foregroundStyle(color(state))
                }
            }
            Text(title).font(.callout).foregroundStyle(state == .waiting ? .secondary : .primary)
        }
    }

    private func color(_ state: StepState) -> Color {
        switch state {
        case .done: return .green
        case .active: return .accentColor
        case .failed: return .red
        case .waiting: return .secondary
        }
    }
}
