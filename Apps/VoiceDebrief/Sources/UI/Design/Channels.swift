import SwiftUI

/// The two ways the app talks to someone, so every message can say which way it travelled
/// (the owner, 14 November 2026: "show the difference between the two ways we talk").
enum ChannelKind: String, CaseIterable, Identifiable, Sendable {
    /// One way: sealed to the recipient's key and dropped in their inbox; the sender cannot read it back.
    case lane
    /// Both ways: both sides hold the vault key and read and write the same encrypted files.
    case sharedVault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lane: "Lane"
        case .sharedVault: "Shared vault"
        }
    }

    /// The badge's words: what it is and which way it goes.
    var badge: String {
        switch self {
        case .lane: "Lane, one way"
        case .sharedVault: "Shared vault, both ways"
        }
    }

    var symbol: String {
        switch self {
        case .lane: "envelope.fill"
        case .sharedVault: "lock.shield.fill"
        }
    }

    /// Green for sending, indigo for vaults: the house colours for each.
    var tint: Color {
        switch self {
        case .lane: DS.Palette.green
        case .sharedVault: DS.Palette.indigo
        }
    }

    /// How it works, in one plain sentence.
    var how: String {
        switch self {
        case .lane:
            "Your device seals the note to their key and drops it in their inbox: you can add to it but not read it back, and the server only ever sees ciphertext."
        case .sharedVault:
            "You and they both hold the vault's key and read and write the same encrypted files, so each of you sees the other's changes appear."
        }
    }

    /// What it is used for now, in one plain sentence.
    var usedFor: String {
        switch self {
        case .lane:
            "Used for voice notes, pictures, messages to agents and handing over a vault's key."
        case .sharedVault:
            "In VoiceDebrief, the Agents vault you share with Claude, where its replies arrive; in SGit Vaults, a vault shared with the people you choose."
        }
    }
}

/// A small mark for any message, note or send: which way it travelled.
struct ChannelBadge: View {
    let kind: ChannelKind
    /// Just the name ("Lane"), for tight rows.
    var short = false

    var body: some View {
        Label(short ? kind.title : kind.badge, systemImage: kind.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 3)
            .background(kind.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(kind.badge)
    }
}

/// An animated drawing of one way of talking. A lane: a sealed envelope travels one way from you to
/// their inbox, with no way back. A shared vault: one vault between you, arrows both ways, files
/// arriving from each side in turn. Still when Reduce Motion is on. `large` for an explainer.
struct ChannelDiagram: View {
    let kind: ChannelKind
    var me: AvatarSubject? = nil
    var them: AvatarSubject? = nil
    var large = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var face: CGFloat { large ? 56 : 36 }
    private var height: CGFloat { large ? 150 : 84 }
    private static let period = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.55
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            GeometryReader { geo in
                let w = geo.size.width
                let y = geo.size.height / 2
                ZStack {
                    switch kind {
                    case .lane: lane(t: t, width: w, y: y)
                    case .sharedVault: sharedVault(t: t, width: w, y: y)
                    }
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: large ? .infinity : 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .lane ? "A note sealed and sent one way, into their inbox"
                                          : "One vault shared between you, read and written by both")
    }

    private var meFace: some View {
        Group {
            if let me { AvatarView(me, size: face) } else { AvatarView(id: "me", kind: .me, size: face) }
        }
    }

    private var themFace: some View {
        Group {
            if let them { AvatarView(them, size: face) } else { AvatarView(id: "them", size: face) }
        }
    }

    private static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

    @ViewBuilder
    private func lane(t: Double, width w: CGFloat, y: CGFloat) -> some View {
        let leftX = face / 2 + 2
        let rightX = w - face / 2 - 2
        let start = leftX + face / 2 + 8
        let end = rightX - face / 2 - 12
        let moving = min(1, t / 0.8)
        let x = start + (end - start) * Self.ease(moving)
        let fade = t < 0.8 ? 1.0 : max(0, 1 - (t - 0.8) / 0.12)

        Path { p in
            p.move(to: CGPoint(x: start, y: y))
            p.addLine(to: CGPoint(x: end, y: y))
        }
        .stroke(kind.tint.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
        Image(systemName: "chevron.right")
            .font(.system(size: face * 0.26, weight: .bold))
            .foregroundStyle(kind.tint.opacity(0.7))
            .position(x: end + 4, y: y)

        meFace.position(x: leftX, y: y)

        ZStack {
            RoundedRectangle(cornerRadius: face * 0.3, style: .continuous).fill(Color(.tertiarySystemFill))
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: face * 0.4, weight: .semibold))
                .foregroundStyle(kind.tint)
        }
        .frame(width: face, height: face)
        .overlay(alignment: .topTrailing) {
            Group {
                if let them { AvatarView(them, size: face * 0.5) } else { AvatarView(id: "them", size: face * 0.5) }
            }
            .offset(x: face * 0.18, y: -face * 0.18)
        }
        .position(x: rightX, y: y)

        Image(systemName: "envelope.fill")
            .font(.system(size: face * 0.42, weight: .semibold))
            .foregroundStyle(kind.tint)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: face * 0.2, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(DS.Palette.navy, in: Circle())
                    .offset(x: face * 0.08, y: face * 0.06)
            }
            .opacity(fade)
            .position(x: x, y: y - face * 0.05)

        if large {
            Text("one way: you cannot read it back")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: (start + end) / 2, y: y + face * 0.62)
        }
    }

    @ViewBuilder
    private func sharedVault(t: Double, width w: CGFloat, y: CGFloat) -> some View {
        let leftX = face / 2 + 2
        let rightX = w - face / 2 - 2
        let midX = w / 2
        let vault = face * 1.1
        // A file from you to the vault in the first half, one from them in the second.
        let fromMe = t < 0.5
        let p = Self.ease(fromMe ? t / 0.5 : (t - 0.5) / 0.5)
        let fileStart = fromMe ? leftX + face / 2 : rightX - face / 2
        let fileEnd = fromMe ? midX - vault / 2 : midX + vault / 2
        let fileX = fileStart + (fileEnd - fileStart) * p
        let arrived = p > 0.92

        meFace.position(x: leftX, y: y)
        themFace.position(x: rightX, y: y)
        ForEach([(leftX + midX) / 2, (midX + rightX) / 2], id: \.self) { x in
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: face * 0.28, weight: .semibold))
                .foregroundStyle(kind.tint.opacity(0.55))
                .position(x: x, y: y + face * 0.42)
        }
        DSIconBadge(symbol: "lock.shield.fill", tint: kind.tint, size: vault)
            .scaleEffect(arrived ? 1.06 : 1)
            .position(x: midX, y: y)
        Image(systemName: "doc.fill")
            .font(.system(size: face * 0.34, weight: .semibold))
            .foregroundStyle(fromMe ? DS.Palette.green : kind.tint)
            .opacity(arrived ? 0 : 1)
            .position(x: fileX, y: y - face * 0.12)
        if arrived {
            Image(systemName: "sparkle")
                .font(.system(size: face * 0.26, weight: .bold))
                .foregroundStyle(DS.Palette.amber)
                .position(x: midX + vault * 0.42, y: y - vault * 0.42)
        }
        if large {
            Text("both of you read and write")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: midX, y: y + face * 0.95)
        }
    }
}

/// "Two ways to talk": both drawings with two plain sentences each; side by side on a wide screen,
/// one above the other on an iPhone.
struct TwoWaysToTalkView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Every note, picture and message travels one of two ways. Each says which with a small badge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        ForEach(ChannelKind.allCases) { card($0) }
                    }
                } else {
                    VStack(spacing: DS.Space.m) {
                        ForEach(ChannelKind.allCases) { card($0) }
                    }
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Two ways to talk")
    }

    private func card(_ kind: ChannelKind) -> some View {
        DSCard {
            HStack {
                Label(kind.title, systemImage: kind.symbol)
                    .font(DS.TypeScale.heading)
                    .foregroundStyle(kind.tint)
                Spacer()
                ChannelBadge(kind: kind)
            }
            ChannelDiagram(kind: kind, me: MyLook.shared.subject(id: "me"),
                           them: AvatarSubject.recipient(named: RecipientStore.builtInName), large: true)
            Text(kind.how).font(.callout)
            Text(kind.usedFor).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
