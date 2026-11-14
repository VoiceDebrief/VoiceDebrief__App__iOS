import SwiftUI

/// A section's symbol on its colour, in a rounded square: the app's icon language.
struct SectionIcon: View {
    let tab: RootTab
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tab.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A card: the surface colour and a hairline, no shadow.
struct DSCard<Content: View>: View {
    var padding: CGFloat = DS.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface()
    }
}

extension View {
    /// The card surface: background, continuous corners and hairline.
    func dsSurface(radius: CGFloat = DS.Radius.card) -> some View {
        background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
    }
}

/// A heading above a group of things, with an optional symbol and a line under it.
struct DSSectionHeader: View {
    let title: String
    var symbol: String?
    var tint: Color = .accentColor
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.xs) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(tint).font(.subheadline.weight(.semibold))
                }
                Text(title).font(DS.TypeScale.heading)
            }
            if let subtitle {
                Text(subtitle).font(DS.TypeScale.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A part of the app as a tile: its drawing, its icon and name, and one line.
struct SectionTile: View {
    let tab: RootTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    Image(tab.art)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                .clipped()
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    SectionIcon(tab: tab, size: 22)
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(tab.line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(DS.Space.s)
        }
        .dsSurface()
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title). \(tab.line)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A state in a word or two, with its symbol and colour: done, working, degraded, failed.
struct StatusPill: View {
    enum Kind {
        case done, working, warning, failed, neutral, vault

        var tint: Color {
            switch self {
            case .done: DS.Palette.green
            case .working: .secondary
            case .warning: DS.Palette.amber
            case .failed: DS.Palette.red
            case .neutral: .secondary
            case .vault: DS.Palette.indigo
            }
        }

        var symbol: String {
            switch self {
            case .done: Icon.done
            case .working: Icon.working
            case .warning: Icon.warning
            case .failed: Icon.failed
            case .neutral: Icon.info
            case .vault: Icon.inVault
            }
        }
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Label(text, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, DS.Space.xs + 2)
            .padding(.vertical, DS.Space.xxs)
            .background(kind.tint.opacity(0.12), in: Capsule())
    }
}

/// The top of a section: its drawing as a banner, with its title and line over a soft fade.
struct SectionHero: View {
    let tab: RootTab
    var title: String?
    var line: String?
    var height: CGFloat = 150
    /// A picture other than the section's own drawing, such as the record screen's first-visit picture.
    var image: String?

    var body: some View {
        Image(image ?? tab.art)
            .resizable()
            .scaledToFill()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? tab.title).font(DS.TypeScale.title).foregroundStyle(.white)
                    Text(line ?? tab.line).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, DS.Palette.navy.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// Nothing here yet: the section's drawing, what will be here, and how it gets here.
struct DSEmptyState: View {
    let tab: RootTab
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(tab.art)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text(title).font(DS.TypeScale.title)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .combine)
    }
}

/// The first row of a section's list: its banner, edge to edge in the row, with no row background.
/// Put it first inside the section's `List` or `Form`.
struct SectionBannerRow: View {
    let tab: RootTab
    var line: String?

    var body: some View {
        Section {
            SectionHero(tab: tab, line: line, height: 128)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
}

/// A note's one mark as a state pill, or nothing.
struct NoteMarkPill: View {
    let mark: NoteMark

    var body: some View {
        switch mark {
        case .working(let text): StatusPill(text: text, kind: .working)
        case .degraded(let text): StatusPill(text: text, kind: .warning)
        case .failed(let text): StatusPill(text: text, kind: .failed)
        case .inVault(let name): StatusPill(text: "In \(name)", kind: .vault)
        case .none: EmptyView()
        }
    }
}

/// Any symbol on a colour in the section icon's rounded square: for rows that are not sections,
/// such as the Lab's experiments.
struct DSIconBadge: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One message in a conversation: yours on the right in the accent colour, theirs on the left beside
/// their avatar, each with a small caption (who and when, or its state).
struct ChatBubble<Content: View>: View {
    let mine: Bool
    var from: AvatarSubject? = nil
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.xs) {
            if mine { Spacer(minLength: DS.Space.xxl) }
            if !mine, let from { AvatarView(from, size: 28) }
            VStack(alignment: mine ? .trailing : .leading, spacing: DS.Space.xxs) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) { content }
                    .font(.callout)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, DS.Space.xs + 1)
                    .background(mine ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !mine { Spacer(minLength: DS.Space.xxl) }
        }
        .frame(maxWidth: .infinity)
    }
}
