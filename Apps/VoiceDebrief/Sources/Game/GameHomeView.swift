import SwiftUI

/// Play: the landing page of the voice games, a section of its own in the sidebar and L03 in the Lab.
/// The two games as large tiles with a picture of their first level, the best score and the last
/// result, and how to start. A tile opens that game.
struct GamePlayView: View {
    private let game = GameController.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                SectionHero(tab: .play, title: "Play", line: "Small games you play by voice. Each move is timed from the end of your words to the screen.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: DS.Space.m)], spacing: DS.Space.m) {
                    ForEach(GameKind.allCases) { kind in
                        NavigationLink {
                            GameScreen(kind: kind)
                        } label: {
                            GameTile(kind: kind, best: game.bestScore(kind),
                                     current: game.state.kind == kind && !game.entries.isEmpty ? game.state : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Side by side when there is room, one above the other on a phone.
                let layout = sizeClass == .regular
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.m))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.m))
                layout {
                    GameHowToStart()
                    if let latest = game.latest {
                        GameLastResult(entry: latest, stats: game.stats)
                    }
                }
                Text("Apple's model on this device: \(OnDeviceModel.status.text). Without it the games still play: the fixed phrases understand directions, numbers and a few words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.ground)
        .navigationTitle("Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One game as a large tile: a picture of its first level, what it is, how far you got.
struct GameTile: View {
    let kind: GameKind
    let best: Int?
    /// The game being played now, if it is this one.
    let current: GameState?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            GameBoardView(state: GameState.start(kind), hint: nil)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(DS.TypeScale.title)
                Spacer()
                Label("Play", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(RootTab.play.tint)
            }
            Text(kind.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: DS.Space.m) {
                Label("\(GameLevels.all(kind).count) levels", systemImage: "square.stack.3d.up")
                if let best { Label("Best \(best) pts", systemImage: "trophy") }
                if let current {
                    Label("Now on level \(current.levelIndex + 1), \(current.points) pts", systemImage: "flag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(DS.Space.m)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.hairline))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(kind.title)")
    }
}

/// How to start, in four steps.
struct GameHowToStart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("How to start").font(DS.TypeScale.heading)
            step(1, "Choose a game.")
            step(2, "Press Listen, then say a move: \u{201C}left\u{201D}, \u{201C}go down two\u{201D}, \u{201C}jump right\u{201D}, \u{201C}open the door\u{201D}.")
            step(3, "Watch the time: from the end of your words to the move, and which engine made it.")
            step(4, "Stuck? Say \u{201C}hint\u{201D}. Or press Voice player and let the game play itself.")
            Text("A few things are hidden.").font(.caption).foregroundStyle(.secondary)
        }
        .gameCard()
    }

    private func step(_ n: Int, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text("\(n)").font(.callout.monospacedDigit().weight(.bold)).foregroundStyle(RootTab.play.tint)
            Text(words).font(.callout)
        }
    }
}

/// The last command and the session's figures, so the page shows how the last game went.
struct GameLastResult: View {
    let entry: GameLogEntry
    let stats: GameStats

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Last time").font(DS.TypeScale.heading)
            if let total = entry.totalMs {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(GameWords.ms(total)).font(DS.TypeScale.number)
                    Text("\u{201C}\(entry.words)\u{201D} \u{2192} \(entry.command ?? "nothing"), by \(entry.engine)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            LabeledContent("Commands", value: "\(stats.commands)")
            LabeledContent("Phrases, mean", value: GameWords.ms(stats.phraseMeanMs))
            LabeledContent("Model, mean", value: GameWords.ms(stats.modelMeanMs))
        }
        .font(.footnote)
        .gameCard()
    }
}
