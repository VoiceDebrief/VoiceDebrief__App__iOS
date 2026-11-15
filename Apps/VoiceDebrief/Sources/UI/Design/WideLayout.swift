import SwiftUI

/// The record screen on an iPad or a Mac (regular width): two columns that scroll on their own, with a line
/// between them you drag to give either side more room (the owner, 15 November 2026: "let me drag and drop
/// resize that middle line... it should remember"). The split is kept as a setting of this screen.
/// The left holds what you do (who it is for, the control, the live words while recording); the right
/// holds what came back. Use it only at regular width; compact keeps the single column. A ScrollViewReader
/// placed around it still reaches ids inside either column, so the live words can still be followed.
struct RecordWideLayout<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    /// The left column's share of the width, kept between visits.
    @AppStorage("vd.record.leftShare") private var leftShare: Double = 0.42
    @State private var dragStart: Double?
    @State private var dragging = false

    static var minColumn: CGFloat { 320 }

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let low = min(Self.minColumn / max(total, 1), 0.5)
            let share = min(max(leftShare, low), 1 - low)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: DS.Space.l) { left }
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.l)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: total * share)

                handle(total: total, low: low)

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) { right }
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.l)
                        .frame(maxWidth: 900, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .background(DS.Palette.ground)
            }
        }
    }

    /// The line between the columns: a thin rule with a grip, a wide area to catch the finger or pointer.
    /// A double tap puts it back in the middle-left default.
    private func handle(total: CGFloat, low: Double) -> some View {
        ZStack {
            Rectangle().fill(Color(.separator)).frame(width: dragging ? 2 : 1)
            Capsule().fill(dragging ? Color.accentColor : Color(.systemGray3))
                .frame(width: 5, height: 44)
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? leftShare
                    if dragStart == nil { dragStart = leftShare; dragging = true }
                    leftShare = min(max(start + value.translation.width / max(total, 1), low), 1 - low)
                }
                .onEnded { _ in dragStart = nil; dragging = false }
        )
        .onTapGesture(count: 2) { withAnimation(.snappy) { leftShare = 0.42 } }
        .accessibilityElement()
        .accessibilityLabel("Column divider")
        .accessibilityValue("\(Int((leftShare * 100).rounded())) percent for the recording side")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: leftShare = min(leftShare + 0.05, 1 - low)
            case .decrement: leftShare = max(leftShare - 0.05, low)
            @unknown default: break
            }
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
