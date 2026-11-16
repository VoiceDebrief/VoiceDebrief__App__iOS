import SwiftUI
import UIKit

/// The live conversation with Claude, on the right of the record screen on iPad and Mac (the owner,
/// 15 November 2026: "when I send you a memo or a decision I should see it there, then your answer; a counter
/// of how many seconds passed; a regular check on the lane; a sense of movement; a timeline of each step, like
/// Chrome's"). Each memo sent to Claude is a card: its status, a clock running until the answer comes, the
/// answer (and a picture if one came with it), and the steps with how long each took. Clear hides what is done.
/// `RecordSidePane` reads the agents vault every ten seconds while it is on screen.
struct LivePanel: View {
    let session: DebriefSession
    let book: VaultBook
    @AppStorage("vd.live.clearedAt") private var clearedAt: Double = 0
    /// Shown as its own tab, so the panel's own heading is left out.
    var showsHeading = true
    @State private var expanded: Set<String> = []
    private var desk: AgentsDesk { AgentsDesk.shared }

    /// A contact that is Claude: the built-in developer lane, or a lane of the owner's own that a conductor
    /// gave only to them ("Claude (your lane)"), so its messages are known to be theirs.
    static func isClaude(_ name: String) -> Bool { name == RecipientStore.builtInName || name.hasPrefix("Claude") }

    /// Notes sent to Claude since the last Clear, newest first.
    private var threads: [Note] {
        session.store.notes
            .filter { note in
                let toClaude = (note.sends ?? []).contains { Self.isClaude($0.to) } || note.pendingSend.map { Self.isClaude($0.name) } == true
                return toClaude && note.createdAt.timeIntervalSince1970 > clearedAt
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func replies(to note: Note) -> [AgentsReport.Message] {
        (desk.report?.messages ?? []).filter { $0.from != "you" && $0.replyTo == note.id }.sorted { $0.at < $1.at }
    }

    private func ack(for note: Note) -> Date? {
        desk.report?.acks?.first { $0.note == note.id }?.receivedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if showsHeading {
                    Label("Live with Claude", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                }
                Spacer()
                if let check = desk.lastCheck {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("checked \(Int(Date().timeIntervalSince(check.at)))s ago")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Button("Clear") { clearedAt = Date().timeIntervalSince1970 }
                    .font(.footnote)
                    .disabled(threads.isEmpty)
            }
            if desk.vaultId.isEmpty {
                Text("Give Claude a vault on the Agents screen, and its answers appear here as they arrive.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if threads.isEmpty {
                Text("Record a note for Claude (or press the green button anywhere) and follow it here: sent, received, answered.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(threads) { note in card(note) }
        }
    }

    // MARK: One memo

    private enum Status { case sending, sent, received, answered, failed }

    private func status(_ note: Note) -> Status {
        if !replies(to: note).isEmpty { return .answered }
        if ack(for: note) != nil { return .received }
        if note.sendProblem != nil { return .failed }
        if (note.sends ?? []).contains(where: { Self.isClaude($0.to) }) { return .sent }
        return .sending
    }

    private func sentAt(_ note: Note) -> Date? {
        note.sends?.last(where: { Self.isClaude($0.to) })?.at
    }

    @ViewBuilder private func card(_ note: Note) -> some View {
        let state = status(note)
        let answers = replies(to: note)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer()
                statusChip(state)
            }
            // A clock from the moment it was sent until the first answer, so the wait can be seen.
            if let sent = sentAt(note) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let end = answers.first.flatMap { desk.seenAt[$0.id] } ?? Date()
                    Text(state == .answered ? "Answered in \(seconds(end.timeIntervalSince(sent)))" : "Waiting \(seconds(Date().timeIntervalSince(sent)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(state == .answered ? .green : .secondary)
                }
            }
            // What the microphone gave while recording, so a silent note explains itself here too.
            if let check = note.run.microphoneCheck {
                Label(check, systemImage: "mic")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(answers) { reply in
                VStack(alignment: .leading, spacing: 6) {
                    Text(reply.text).font(.callout)
                    if let path = reply.image, let data = desk.images[path], let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(note.id) },
                                                set: { if $0 { expanded.insert(note.id) } else { expanded.remove(note.id) } })) {
                Waterfall(steps: steps(note))
            } label: {
                Text("Timeline").font(.caption)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: answers.count)
    }

    private func statusChip(_ state: Status) -> some View {
        let look: (String, Color, String) = switch state {
        case .sending: ("Sending", .secondary, "arrow.up.circle")
        case .sent: ("Sent", .blue, "paperplane.fill")
        case .received: ("Claude has it", .orange, "tray.and.arrow.down.fill")
        case .answered: ("Answered", .green, "checkmark.circle.fill")
        case .failed: ("Not sent", .red, "exclamationmark.triangle.fill")
        }
        return Label(look.0, systemImage: look.2)
            .font(.caption.weight(.semibold))
            .foregroundStyle(look.1)
            .symbolEffect(.pulse, isActive: state == .sent || state == .received)
    }

    private func seconds(_ s: TimeInterval) -> String {
        s < 60 ? "\(Int(s))s" : "\(Int(s) / 60)m \(Int(s) % 60)s"
    }

    /// The steps, each from its start to its end, from the moment recording began.
    private func steps(_ note: Note) -> [Waterfall.Step] {
        var out: [Waterfall.Step] = []
        let start = note.createdAt
        let recordEnd = start.addingTimeInterval(note.run.audioSeconds ?? 0)
        out.append(.init(name: "Recorded", from: start, to: recordEnd))
        let writing = note.run.steps.reduce(0) { $0 + $1.seconds }
        let writtenUp = recordEnd.addingTimeInterval(writing)
        out.append(.init(name: "Written up on the device", from: recordEnd, to: writtenUp))
        if let sent = sentAt(note) {
            out.append(.init(name: "Encrypted and sent", from: writtenUp, to: max(sent, writtenUp)))
            if let got = ack(for: note) {
                out.append(.init(name: "Reached Claude", from: sent, to: max(got, sent)))
                if let reply = replies(to: note).first {
                    out.append(.init(name: "Claude answered", from: got, to: max(reply.at, got)))
                    if let seen = desk.seenAt[reply.id] {
                        out.append(.init(name: "Shown here", from: reply.at, to: max(seen, reply.at)))
                    }
                }
            }
        }
        return out
    }
}

/// Steps drawn as bars along one time line, each with how long it took (like a browser's network timeline).
struct Waterfall: View {
    struct Step: Identifiable {
        let name: String
        let from: Date
        let to: Date
        var id: String { name }
        var seconds: TimeInterval { to.timeIntervalSince(from) }
    }
    let steps: [Step]

    var body: some View {
        let start = steps.map(\.from).min() ?? Date()
        let end = steps.map(\.to).max() ?? start
        let total = max(end.timeIntervalSince(start), 0.001)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step.name).font(.caption2)
                        Spacer()
                        Text(Self.format(step.seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        let x = proxy.size.width * step.from.timeIntervalSince(start) / total
                        let w = max(proxy.size.width * step.seconds / total, 2)
                        Capsule().fill(Color.accentColor.opacity(0.7))
                            .frame(width: w, height: 6)
                            .offset(x: x)
                    }
                    .frame(height: 6)
                }
            }
            Text("In all \(Self.format(total))").font(.caption2.weight(.semibold))
        }
        .padding(.top, 4)
    }

    static func format(_ s: TimeInterval) -> String {
        s < 1 ? String(format: "%.1fs", s) : s < 60 ? "\(Int(s.rounded()))s" : "\(Int(s) / 60)m \(Int(s) % 60)s"
    }
}
