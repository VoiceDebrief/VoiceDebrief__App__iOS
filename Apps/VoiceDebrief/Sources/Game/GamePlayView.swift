import SwiftUI

/// Experiment L03: play by voice, and see how long each command took to show.
struct GamePlayView: View {
    @AppStorage("vd.localeId") private var localeId = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let game = GameController.shared
    private let player = GameVoicePlayer.shared
    @State private var typed = ""

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: DS.Space.l) {
                    ScrollView {
                        VStack(spacing: DS.Space.m) {
                            header
                            board
                            latency
                            voice
                        }
                        .padding(DS.Space.m)
                    }
                    ScrollView {
                        panel.padding(DS.Space.m)
                    }
                    .frame(width: 380)
                }
            } else {
                ScrollView {
                    VStack(spacing: DS.Space.m) {
                        header
                        board
                        latency
                        voice
                        panel
                    }
                    .padding(DS.Space.m)
                }
            }
        }
        .background(DS.Palette.ground)
        .navigationTitle("Play")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { game.prepareModel() }
        .onDisappear {
            player.stop()
            Task { await game.stopListening() }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Picker("Game", selection: Binding(get: { game.state.kind }, set: { game.choose($0) })) {
                ForEach(GameKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Text("Level \(game.state.levelIndex + 1): \(game.state.level.title)")
                .font(DS.TypeScale.heading)
            Text(game.state.level.story)
                .font(.footnote)
                .foregroundStyle(.secondary)
            GameScoreLine(state: game.state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var board: some View {
        VStack(spacing: DS.Space.xs) {
            GameBoardView(state: game.state, hint: game.hint)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: sizeClass == .regular ? 520 : 360)
            Text(game.message)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let hint = game.hint {
                Label(hint.source == "model" ? "\(hint.words) (the model's clue)" : hint.words, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(Color(light: 0xB98500, dark: 0xF0B429))
            }
            if game.state.status != .playing {
                HStack {
                    if game.state.status == .levelWon {
                        Button("Next level") { game.tap(.nextLevel) }.buttonStyle(.borderedProminent)
                    }
                    Button("Restart") { game.tap(.restart) }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var latency: some View {
        GameLatencyCard(entry: game.latest)
    }

    private var voice: some View {
        VStack(spacing: DS.Space.s) {
            Button {
                Task {
                    if game.listening { await game.stopListening() } else { await game.startListening(localeId: localeId) }
                }
            } label: {
                Label(game.listening ? "Stop listening" : "Listen", systemImage: game.listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(game.listening ? DS.Palette.red : DS.Palette.green)
            if game.listening {
                Text(liveWords)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let problem = game.problem {
                Text(problem).font(.footnote).foregroundStyle(DS.Palette.red)
            }
            HStack {
                Button {
                    if player.playing { player.stop() } else { player.start(game, localeId: localeId) }
                } label: {
                    Label(player.playing ? "Stop the voice player" : "Voice player", systemImage: player.playing ? "person.wave.2.fill" : "person.wave.2")
                }
                .buttonStyle(.bordered)
                Spacer()
                if let saying = player.saying {
                    Text("says \u{201C}\(saying)\u{201D}").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(game.listening
                 ? "The voice player speaks its commands; the microphone hears them like yours."
                 : "The voice player speaks its commands. Press Listen first for them to go through the microphone; otherwise its words are handed in directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                TextField("Or type: go left two", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit(sendTyped)
                Button("Go", action: sendTyped)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            GameEngineSection(game: game)
            GameToolsSection(tools: game.tools, tokens: game.tokensNow)
            GameStatsSection(stats: game.stats, found: game.state.found)
            GameLogSection(game: game)
        }
    }

    private var liveWords: String {
        let text = (String(game.liveSettled.suffix(120)) + " " + game.liveVolatile).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Listening. Say a direction: left, right, up, down." : text
    }

    private func sendTyped() {
        game.hear(typed, source: "typed")
        typed = ""
    }
}

/// Gold, keys, lives, moves left and points, in one line.
struct GameScoreLine: View {
    let state: GameState

    var body: some View {
        HStack(spacing: DS.Space.s) {
            chip("circle.fill", "\(state.gold)/\(state.goldTotal)", Color(dsHex: 0xF0B429))
            if state.keys > 0 { chip("key.fill", "\(state.keys)", Color(dsHex: 0xB98500)) }
            chip("heart.fill", "\(state.lives)", DS.Palette.red)
            chip("figure.walk", "\(state.movesLeft)", Color.secondary)
            Spacer()
            Text("\(state.points) pts").font(.callout.monospacedDigit().weight(.semibold))
        }
        .font(.footnote.monospacedDigit())
    }

    private func chip(_ symbol: String, _ text: String, _ colour: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(text)
        }
    }
}

/// The time of the last command, large, and its parts.
struct GameLatencyCard: View {
    let entry: GameLogEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry, let total = entry.totalMs {
                HStack(alignment: .firstTextBaseline) {
                    Text(GameWords.ms(total))
                        .font(DS.TypeScale.number)
                        .foregroundStyle(total < 500 ? DS.Palette.green : (total < 1500 ? DS.Palette.amber : DS.Palette.red))
                    Text("by \(entry.engine)\(entry.early ? ", before the words settled" : "")\(total < 0 ? ", before the voice finished" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("\u{201C}\(entry.words)\u{201D} \u{2192} \(entry.command ?? "nothing")")
                    .font(.footnote)
                    .lineLimit(2)
                Text(GameLatencyWords.parts(entry))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Say a command. The time from the end of your words to the move is shown here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}

enum GameLatencyWords {
    static func parts(_ entry: GameLogEntry) -> String {
        var parts: [String] = []
        if let settle = entry.settleMs { parts.append("words settled \(GameWords.ms(settle))") }
        parts.append("phrases \(String(format: "%.2f", entry.phraseMs)) ms")
        if let turn = entry.model {
            let what = entry.shadow ? "model (compare)" : "model"
            if let first = turn.firstCallMs {
                parts.append("\(what) \(GameWords.ms(first))\(turn.prewarmed ? ", prewarmed" : "")")
            } else {
                parts.append("\(what) \(GameWords.ms(turn.totalMs)), \(turn.error?.kind ?? "no tool")")
            }
            parts.append("~\(turn.tokens.total) tokens")
            parts.append("~\(GameWords.energy(turn.energyMilliwattHours))")
            if let proposed = entry.modelCommand, entry.shadow { parts.append("model would: \(proposed)") }
        }
        parts.append("thermal \(entry.thermal)")
        return parts.joined(separator: " · ")
    }
}

struct GameEngineSection: View {
    @Bindable var game: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Engine").font(DS.TypeScale.heading)
            Picker("Engine", selection: $game.mode) {
                ForEach(GameEngineMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: game.mode) { game.prepareModel() }
            Toggle("Ask the model too, to compare", isOn: $game.shadowModel)
            Toggle("Act before the words settle", isOn: $game.actEarly)
            Text("Phrases: the code's fixed words, no model. Model: Apple's on-device model, one sentence at a time with only this turn's tools; its first tool call ends the request. Both: phrases first, the model when they find nothing. Model: \(OnDeviceModel.status.text).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if game.modelBusy {
                HStack(spacing: DS.Space.xs) {
                    ProgressView()
                    Text("Asking the model").font(.footnote)
                }
            }
        }
        .gameCard()
    }
}

struct GameToolsSection: View {
    let tools: [GameToolSpec]
    let tokens: GameTokenEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("This turn's tools").font(DS.TypeScale.heading)
            if tools.isEmpty {
                Text("None: nothing can be done from here.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(tools, id: \.name) { tool in
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name).font(.footnote.monospaced().weight(.semibold))
                    Text(tool.description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("About \(tokens.total) tokens a request (instructions \(tokens.instructions), prompt \(tokens.prompt), tools \(tokens.tools))\(tokens.context.map { " of \($0)" } ?? ""). Estimated at four characters a token.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .gameCard()
    }
}

struct GameStatsSection: View {
    let stats: GameStats
    let found: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Measured").font(DS.TypeScale.heading)
            LabeledContent("Commands", value: "\(stats.commands)")
            LabeledContent("Phrases acted, mean", value: "\(stats.phraseActed), \(GameWords.ms(stats.phraseMeanMs))")
            LabeledContent("Model acted, mean", value: "\(stats.modelActed), \(GameWords.ms(stats.modelMeanMs))")
            LabeledContent("Model requests, to first call", value: "\(stats.modelRequests), \(GameWords.ms(stats.modelFirstCallMeanMs))")
            LabeledContent("Model energy, estimated", value: GameWords.energy(stats.modelEnergyMilliwattHours))
            LabeledContent("Not understood", value: "\(stats.notUnderstood)")
            LabeledContent("Secrets found", value: "\(found.count)")
            Text("Energy assumes \(String(format: "%.0f", GameEnergy.assumedWatts)) W while the model runs: an estimate, not a measurement. The phrases cost next to nothing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .gameCard()
    }
}

struct GameLogSection: View {
    let game: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Log").font(DS.TypeScale.heading)
            if game.entries.isEmpty {
                Text("Every command is kept here while the app is open.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(game.entries.prefix(40)) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("\u{201C}\(entry.words)\u{201D}").font(.footnote).lineLimit(1)
                        Spacer()
                        Text(GameWords.ms(entry.totalMs)).font(.footnote.monospacedDigit())
                    }
                    Text("\(entry.source), \(entry.engine): \(entry.command ?? "nothing")\(entry.accepted == false ? " (refused)" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
            if !game.entries.isEmpty {
                ShareLink(item: game.log.json) {
                    Label("Share the log as JSON", systemImage: "square.and.arrow.up")
                }
                Button("Clear the log", role: .destructive) { game.clearLog() }
            }
        }
        .gameCard()
    }
}

extension View {
    func gameCard() -> some View {
        padding(DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}
