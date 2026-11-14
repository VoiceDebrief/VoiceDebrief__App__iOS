import SwiftUI

/// The Guide: one place to find out what exists, what changed and what is coming, for the owner, a new
/// tester and a teammate alike (the owner's request of 14 November 2026: "I wake up and I go, okay, what
/// has been created?"). After the owner found it "not much to do in there" on a wide Mac window, it opens
/// on the latest release card, with buttons that open the sections the card names; the guides are picture
/// tiles; the ideas are what is in progress now. On a wide screen it has two columns: the list on the
/// left, the chosen card, guide or list on the right. Content comes from the bundled data.
struct GuideView: View {
    /// Opens a section of the app (the shell's tab), for the Try and Open buttons.
    var go: (RootTab) -> Void = { _ in }

    private let ideas = IdeaBook.bundled()
    private let history = VersionHistory.bundled()
    private let guides = GuideBook.bundled()
    private let articles = ArticleBook.bundled()
    private let current = AppInfo.shortVersion()
    @AppStorage(WhatsNewMemory.key) private var lastSeen = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: GuideItem?
    /// Browser-like history on a wide screen (the owner: swiping back worked, swiping forward should
    /// return): what was shown before, and what was left by going back.
    @State private var back: [GuideItem] = []
    @State private var forward: [GuideItem] = []
    @State private var movingInHistory = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    home(wide: true)
                        .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 520)
                } detail: {
                    NavigationStack {
                        detail(selection ?? .latestCard)
                            .id(selection ?? .latestCard)
                            .toolbar {
                                ToolbarItemGroup(placement: .navigation) {
                                    Button { goBack() } label: { Image(systemName: "chevron.left") }
                                        .disabled(back.isEmpty)
                                        .accessibilityLabel("Back")
                                        .keyboardShortcut("[", modifiers: .command)
                                    Button { goForward() } label: { Image(systemName: "chevron.right") }
                                        .disabled(forward.isEmpty)
                                        .accessibilityLabel("Forward")
                                        .keyboardShortcut("]", modifiers: .command)
                                }
                            }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 40).onEnded { v in
                                    guard abs(v.translation.width) > 100, abs(v.translation.height) < 60 else { return }
                                    if v.translation.width > 0 { goBack() } else { goForward() }
                                }
                            )
                    }
                }
                .onChange(of: selection) { old, new in
                    if movingInHistory { movingInHistory = false; return }
                    guard (old ?? .latestCard) != (new ?? .latestCard) else { return }
                    back.append(old ?? .latestCard)
                    forward.removeAll()
                }
            } else {
                NavigationStack {
                    home(wide: false)
                        .navigationDestination(item: $selection) { detail($0) }
                }
            }
        }
        .onAppear { WhatsNewMemory.seedIfNeeded(current: current) }
    }

    private func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(selection ?? .latestCard)
        movingInHistory = previous != selection
        selection = previous
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(selection ?? .latestCard)
        movingInHistory = next != selection
        selection = next
    }

    private func home(wide: Bool) -> some View {
        GuideHome(ideas: ideas, history: history, guides: guides, articles: articles, current: current,
                  lastSeen: lastSeen, wide: wide, selection: $selection, go: go)
    }

    @ViewBuilder
    private func detail(_ item: GuideItem) -> some View {
        switch item {
        case .latestCard:
            if let history { ReleaseCardDetail(history: history, current: current, go: go) }
            else { DSEmptyState(tab: .guide, title: "No release notes", message: "This build carries no release notes.") }
        case .whatsNew:
            if let history { WhatsNewView(history: history, current: current) }
        case .guide(let id):
            if let book = guides, let g = book.guides.first(where: { $0.id == id }) {
                FeatureGuideView(guide: g, ideas: ideas, pictures: g.pictures ?? book.pictures, go: go)
            }
        case .ideas(let status):
            if let ideas { IdeasView(book: ideas, status: status) }
        case .articles:
            if let articles { ArticlesView(book: articles) }
        }
    }
}

/// What the Guide can show on its right-hand side (or push, on a phone).
enum GuideItem: Hashable {
    case latestCard
    case whatsNew
    case guide(String)
    case ideas(String?)
    case articles
}

/// The Guide's list: the latest card, what is new, the guides as picture tiles, what is in progress.
struct GuideHome: View {
    let ideas: IdeaBook?
    let history: VersionHistory?
    let guides: GuideBook?
    var articles: ArticleBook? = nil
    let current: String
    let lastSeen: String
    var wide: Bool = false
    @Binding var selection: GuideItem?
    var go: (RootTab) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DS.Space.s)]

    var body: some View {
        let unseen = history?.since(lastSeen, current: current) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if let card = history?.latestCard(current: current) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSSectionHeader(title: "Latest release", symbol: "sparkles")
                        Button { selection = .latestCard } label: {
                            ReleaseCardTile(version: card.version, text: card.text, selected: wide && (selection ?? .latestCard) == .latestCard)
                        }
                        .buttonStyle(.plain)
                        TryButtons(text: card.text, go: go)
                    }
                }

                if history != nil {
                    choice(.whatsNew, symbol: "shippingbox",
                           title: unseen.isEmpty ? "Every version" : (unseen.count == 1 ? "1 version since you last looked" : "\(unseen.count) versions since you last looked"),
                           line: "What changed in each release, newest first", badge: !unseen.isEmpty)
                }

                if let guides, !guides.guides.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSSectionHeader(title: "How to use it", symbol: "book.pages")
                        LazyVGrid(columns: columns, spacing: DS.Space.s) {
                            ForEach(guides.guides) { g in
                                Button { selection = .guide(g.id) } label: {
                                    GuideTile(guide: g, selected: wide && selection == .guide(g.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let ideas {
                    InProgressNow(book: ideas, selection: $selection, wide: wide)
                }

                if let articles, !articles.articles.isEmpty {
                    choice(.articles, symbol: "doc.richtext", title: "Articles (\(articles.articles.count))",
                           line: "Where the project is going: positions, briefs and journeys", badge: false)
                }

                HStack(spacing: DS.Space.m) {
                    Link(destination: AppInfo.site.appendingPathComponent("ideas/index.html")) { Label("Ideas on the web", systemImage: "globe") }
                    Link(destination: AppInfo.site.appendingPathComponent("built/index.html")) { Label("What is built", systemImage: "checklist") }
                }
                .font(.footnote)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: wide ? .infinity : 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.ground)
        .navigationTitle("Guide")
    }

    private func choice(_ item: GuideItem, symbol: String, title: String, line: String, badge: Bool) -> some View {
        Button { selection = item } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(DS.TypeScale.heading)
                        if badge { Circle().fill(Color.accentColor).frame(width: 8, height: 8) }
                    }
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(DS.Space.m)
            .contentShape(Rectangle())
            .dsSurface()
            .overlay(GuideStyle.selectionRing(wide && selection == item))
        }
        .buttonStyle(.plain)
    }
}

/// How the Guide looks, in one place for the design session.
enum GuideStyle {
    static let callout = Color(red: 0.9, green: 0.12, blue: 0.31)    // the arrows' colour in the pictures
    static let cardInk = DS.Palette.mint
    static let cardGround = DS.Palette.navy

    @ViewBuilder
    static func selectionRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0)
    }
}

/// A release card that fits its width and takes the height its lines need.
struct FittedCard: View {
    let text: String
    var maxFont: CGFloat = 17

    var body: some View {
        let lines = CGFloat(text.components(separatedBy: "\n").count)
        ViewThatFitsWidth { width in
            let size = max(6, min(maxFont, (width - 2 * DS.Space.m) / (72 * 0.61)))
            Text(text)
                .font(.system(size: size, design: .monospaced))
                .foregroundStyle(GuideStyle.cardInk)
                .lineSpacing(0)
                .fixedSize()
                .padding(DS.Space.m)
                .frame(width: width, height: lines * size * 1.25 + 2 * DS.Space.m, alignment: .topLeading)
        }
        .background(GuideStyle.cardGround, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: #"[+|\-]{2,}|[|+]"#, with: " ", options: .regularExpression))
    }
}

/// Gives its content the width it is offered and takes the height the content reports.
struct ViewThatFitsWidth<Content: View>: View {
    @ViewBuilder var content: (CGFloat) -> Content
    @State private var width: CGFloat = 320

    var body: some View {
        content(width)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The latest card as a tile at the top of the Guide.
struct ReleaseCardTile: View {
    let version: String
    let text: String
    var selected: Bool = false

    var body: some View {
        FittedCard(text: text, maxFont: 13)
            .overlay(GuideStyle.selectionRing(selected))
    }
}

/// One button per section a card's WHERE and TRY lines name; each opens that section.
struct TryButtons: View {
    let text: String
    let go: (RootTab) -> Void

    var body: some View {
        let tabs = ReleaseCard.sections(in: text).filter { $0 != .guide }
        if !tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(tabs) { tab in
                        Button { go(tab) } label: {
                            Label("Try \(tab.title)", systemImage: tab.symbol)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tab.tint)
                    }
                }
            }
        }
    }
}

/// The latest card large, its Try buttons, and that version's notes.
struct ReleaseCardDetail: View {
    let history: VersionHistory
    let current: String
    let go: (RootTab) -> Void

    var body: some View {
        let entry = history.all(current: current).first { $0.art?.isEmpty == false }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                if let entry, let card = entry.art?.first {
                    Text(entry.version == current ? "In this build, \(entry.version)" : "Released in \(entry.version)")
                        .font(DS.TypeScale.eyebrow).foregroundStyle(.secondary)
                    FittedCard(text: card, maxFont: 19)
                    TryButtons(text: card, go: go)
                    ForEach(Array((entry.art ?? []).dropFirst().enumerated()), id: \.offset) { FittedCard(text: $0.element, maxFont: 19) }
                    if !entry.notes.isEmpty {
                        DSSectionHeader(title: "The notes", symbol: "text.alignleft")
                        ForEach(Array(entry.notes.enumerated()), id: \.offset) {
                            Text($0.element).lineSpacing(3).textSelection(.enabled)
                        }
                    }
                    if let url = URL(string: entry.url) {
                        Link(destination: url) { Label("This version's page", systemImage: "arrow.up.right.square") }
                    }
                } else {
                    DSEmptyState(tab: .guide, title: "No release card yet", message: "A release card is written with a change; the next release will carry one.")
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.ground)
        .navigationTitle("Latest release")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A guide as a tile: the top of its first picture, its title, and which app.
struct GuideTile: View {
    let guide: FeatureGuide
    var selected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let name = guide.steps.first?.image, let url = GuideBook.pictureURL(name), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 150, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(guide.app == "SGit Vaults" ? "SGit Vaults" : "\(guide.steps.count) picture\(guide.steps.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(DS.Space.s)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        }
        .dsSurface()
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(GuideStyle.selectionRing(selected))
        .accessibilityElement(children: .combine)
    }
}

/// The ideas, short: a count per status (each opens that list) and what is in progress now.
struct InProgressNow: View {
    let book: IdeaBook
    @Binding var selection: GuideItem?
    var wide: Bool = false

    var body: some View {
        let now = book.ideas.filter { $0.status == "in-progress" && $0.kind != "feature" }
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(title: "Ideas, and where they stand", symbol: "lightbulb")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(book.statuses) { s in
                        Button { selection = .ideas(s.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(book.counts[s.id] ?? 0)").font(DS.TypeScale.number).foregroundStyle(IdeaStyle.tint(s.id))
                                Text(s.label).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(DS.Space.s)
                            .frame(minWidth: 96, alignment: .leading)
                            .dsSurface()
                            .overlay(GuideStyle.selectionRing(wide && selection == .ideas(s.id)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !now.isEmpty {
                Text("In progress now").font(DS.TypeScale.heading).padding(.top, DS.Space.xxs)
                VStack(spacing: 0) {
                    ForEach(now.prefix(6)) { idea in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                            Image(systemName: IdeaStyle.symbol(idea.status)).foregroundStyle(IdeaStyle.tint(idea.status))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(idea.title).font(.subheadline)
                                Text([idea.kindLabel, idea.app == "VoiceDebrief" ? nil : idea.app, idea.places.first].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, DS.Space.xs)
                        .padding(.horizontal, DS.Space.s)
                        Divider().padding(.leading, DS.Space.s)
                    }
                    Button { selection = .ideas("in-progress") } label: {
                        Text(now.count > 6 ? "All \(now.count) in progress" : "Open the list").font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.s)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .dsSurface()
            }
            Button { selection = .ideas(nil) } label: {
                Label("Every idea (\(book.ideas.count)), searchable", systemImage: "magnifyingglass").font(.subheadline)
            }
        }
    }
}
