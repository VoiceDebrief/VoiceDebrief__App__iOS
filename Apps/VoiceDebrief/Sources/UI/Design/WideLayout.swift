import SwiftUI

/// The record screen on an iPad or a Mac (regular width): two columns that scroll on their own.
/// The left holds what you do (who it is for, the control, the live words while recording); the right
/// holds what came back (recent notes, Claude's replies). Held to readable widths, so a full-width
/// Mac window is not one narrow column in the middle (the owner, 14 November 2026).
/// Use it only at regular width; compact keeps the single column. A ScrollViewReader placed around it
/// still reaches ids inside either column, so the live words can still be followed.
struct RecordWideLayout<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Space.l) { left }
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.l)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 380, idealWidth: 460, maxWidth: 520)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) { right }
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.l)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .background(DS.Palette.ground)
        }
    }
}

/// A heading for a column of the wide layout: a symbol, a title, an optional count and a trailing action.
struct WideColumnHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            DSIconBadge(symbol: symbol, tint: tint, size: 26)
            Text(title).font(DS.TypeScale.heading)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(tint)
            }
            Spacer()
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension WideColumnHeader where Trailing == EmptyView {
    init(title: String, symbol: String, tint: Color = .accentColor, count: Int? = nil) {
        self.init(title: title, symbol: symbol, tint: tint, count: count) { EmptyView() }
    }
}

/// Claude's replies as a conversation, newest last, for the wide record screen's right column (or
/// anywhere): each a bubble on the left beside the conductor's face. With none, it says how replies
/// arrive. `limit` keeps the column short; the full list is in Messages.
struct ClaudeRepliesPanel: View {
    let replies: [AgentsReport.Message]
    var limit = 6
    /// The agents vault has been given, so replies can arrive.
    var connected = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            WideColumnHeader(title: "Messages from Claude", symbol: Icon.send,
                             tint: DS.Palette.indigo, count: replies.count) {
                ChannelBadge(kind: .sharedVault, short: true)
            }
            if replies.isEmpty {
                Text(connected
                     ? "Nothing yet. Claude's replies appear here as they arrive in your agents vault."
                     : "Give Claude a vault on the Agents screen and its replies appear here, encrypted, readable only on your devices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(replies.sorted { $0.at < $1.at }.suffix(limit))) { message in
                    ChatBubble(mine: false, from: AvatarSubject.recipient(named: RecipientStore.builtInName),
                               caption: message.at.formatted(date: .abbreviated, time: .shortened)) {
                        Text(message.text)
                    }
                }
            }
        }
        .padding(DS.Space.m)
        .dsSurface()
    }
}
