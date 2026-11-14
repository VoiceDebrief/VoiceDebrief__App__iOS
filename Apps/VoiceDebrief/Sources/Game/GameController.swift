import AVFoundation
import Foundation
import Observation

/// Experiment L03, the voice game: sentences come in (spoken, typed, or said by the voice player), the
/// phrases or the model turn each into a command, the rules apply it, and every step is timed. The
/// code owns the state; the model only proposes.
@MainActor
@Observable
final class GameController {
    static let shared = GameController()

    /// How long the live words must stay the same before the phrases act on them unsettled.
    static let earlyPauseMs = 250

    private(set) var state: GameState
    private(set) var message: String
    /// Newest first.
    private(set) var entries: [GameLogEntry] = []
    private(set) var hint: GameHint?
    private(set) var listening = false
    private(set) var liveSettled = ""
    private(set) var liveVolatile = ""
    private(set) var problem: String?
    private(set) var modelBusy = false
    private(set) var wrongStreak = 0
    /// The model's clues, newest first.
    private(set) var hintTurns: [GameModelTurn] = []
    private(set) var hintAsking = false
    private(set) var movesSinceProgress = 0

    var mode: GameEngineMode = .both
    /// Ask the model as well when the phrases acted, to compare; it changes nothing.
    var shadowModel = true
    /// Let the phrases act on live words before they settle, once they have held still for a moment.
    var actEarly = true

    private struct Pending {
        let id: String
        let act: Bool
        let words: String
        /// The state the sentence was said in, for a request made only to compare.
        let basis: GameState?
    }

    private let live = LiveTranscriber()
    private let engine = GameModelEngine()
    private var consumed = 0
    private var lastVolatileChange: Date?
    private var early: (id: String, command: GameCommand)?
    private var earlyTask: Task<Void, Never>?
    private var waiting: [Pending] = []
    private var worker: Task<Void, Never>?
    private var counter = 0
    /// The voice player is speaking, or finished at this moment: what the microphone hears now is its.
    private var playerSpeaking = false
    private var playerFinishedAt: Date?
    private var playerEntriesWhileSpeaking: [String] = []

    init(kind: GameKind = .boxes) {
        let start = GameState.start(kind)
        state = start
        message = start.level.story
        best = UserDefaults.standard.dictionary(forKey: Self.bestKey) as? [String: Int] ?? [:]
    }

    var stats: GameStats { GameStats.of(entries) }

    private static let bestKey = "vd.game.best"
    /// The best score reached in each game on this device, kept across launches.
    private(set) var best: [String: Int] = [:]

    func bestScore(_ kind: GameKind) -> Int? { best[kind.rawValue] }

    private func keepBest() {
        guard state.status == .levelWon || state.status == .won else { return }
        let key = state.kind.rawValue
        guard state.points > (best[key] ?? 0) else { return }
        best[key] = state.points
        UserDefaults.standard.set(best, forKey: Self.bestKey)
    }
    /// The words of the sentence being said now: settled but not yet taken, then the part that may still change.
    var hearingSettled: String { String(liveSettled.dropFirst(min(consumed, liveSettled.count))).trimmingCharacters(in: .whitespacesAndNewlines) }
    var hearingVolatile: String { liveVolatile.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The sentences heard through the microphone, newest first, with what became of each.
    var heard: [GameLogEntry] { entries.filter { $0.source == "spoken" || $0.source == "player" } }
    /// The newest sentence that changed or tried to change the game.
    var latest: GameLogEntry? { entries.first { $0.appliedAt != nil } }
    var tools: [GameToolSpec] { GameToolScope.tools(for: state) }
    var tokensNow: GameTokenEstimate {
        GameTokenEstimate.estimate(instructions: GameModelEngine.rulesInstructions,
                                   prompt: GameModelEngine.prompt(words: "go left two", state: state),
                                   tools: tools, context: OnDeviceModel.contextSize)
    }

    func choose(_ kind: GameKind) {
        state = GameState.start(kind)
        message = state.level.story
        resetProgress()
        prepareModel()
    }

    private func resetProgress() {
        hint = nil
        wrongStreak = 0
        movesSinceProgress = 0
    }

    // MARK: Sentences in

    private func newEntry(words: String, source: String, endedAt: Date, settledAt: Date? = nil, early: Bool = false) -> String {
        counter += 1
        var source = source
        var endedAt = endedAt
        let id = "g\(counter)"
        // Heard while the voice player spoke, or just after: its words, timed from the end of its speech.
        if source == "spoken" {
            if playerSpeaking {
                source = "player"
                playerEntriesWhileSpeaking.append(id)
            } else if let finished = playerFinishedAt, Date().timeIntervalSince(finished) < 5 {
                source = "player"
                endedAt = finished
            }
        }
        let entry = GameLogEntry(id: id, game: state.kind, level: state.levelIndex + 1, words: words, source: source,
                                 endedAt: endedAt, settledAt: settledAt, early: early,
                                 thermal: GameEnergy.thermalWords(ProcessInfo.processInfo.thermalState))
        entries.insert(entry, at: 0)
        return entry.id
    }

    /// One sentence into the game.
    @discardableResult
    func hear(_ words: String, source: String, endedAt: Date = Date(), settledAt: Date? = nil, early: Bool = false) -> String? {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !LabTriggerMatcher.words(text).isEmpty else { return nil }
        let id = newEntry(words: text, source: source, endedAt: endedAt, settledAt: settledAt, early: early)
        let started = Date()
        let phrase = GamePhrases.parse(text, kind: state.kind)
        let phraseMs = Date().timeIntervalSince(started) * 1000
        update(id) {
            $0.phrase = phrase?.words
            $0.phraseMs = phraseMs
        }
        switch mode {
        case .phrases:
            if let phrase { act(phrase, entryId: id, engine: "phrases") } else { notUnderstood(id, words: text) }
        case .model:
            queueModel(Pending(id: id, act: true, words: text, basis: nil))
        case .both:
            if let phrase {
                let before = state
                act(phrase, entryId: id, engine: "phrases")
                if shadowModel && Self.worthComparing(phrase) && waiting.isEmpty && !modelBusy {
                    queueModel(Pending(id: id, act: false, words: text, basis: before))
                }
            } else {
                queueModel(Pending(id: id, act: true, words: text, basis: nil))
            }
        }
        return id
    }

    // MARK: The voice player

    func playerStarted() {
        playerSpeaking = true
        playerFinishedAt = nil
        playerEntriesWhileSpeaking = []
    }

    /// The voice player's speech ended. Sentences acted on while it was still speaking are timed from
    /// this moment too, so their time is below zero: acted on before the voice finished.
    func playerFinished(at: Date) {
        playerSpeaking = false
        playerFinishedAt = at
        for id in playerEntriesWhileSpeaking { update(id) { $0.endedAt = at } }
        playerEntriesWhileSpeaking = []
    }

    /// A button pressed instead of a word said.
    func tap(_ command: GameCommand) {
        let id = newEntry(words: command.words, source: "tap", endedAt: Date())
        act(command, entryId: id, engine: "tap")
    }

    private static func worthComparing(_ command: GameCommand) -> Bool {
        switch command {
        case .move, .jump, .climb, .unlock, .nextLevel, .restart: return true
        case .hint, .knock, .thanks: return false
        }
    }

    /// The rules apply a command. The only place the state changes.
    private func act(_ command: GameCommand, entryId: String, engine: String) {
        if command == .hint {
            showHint(asked: true)
            let words = hint?.words ?? "No clue to give."
            message = words
            update(entryId) {
                $0.engine = engine
                $0.command = command.words
                $0.accepted = true
                $0.outcome = words
                $0.appliedAt = Date()
            }
            return
        }
        let result = GameRules.apply(command, to: state)
        state = result.state
        let appliedAt = Date()
        keepBest()
        message = result.message
        update(entryId) {
            $0.engine = engine
            $0.command = command.words
            $0.accepted = result.accepted
            $0.outcome = result.message
            $0.appliedAt = appliedAt
        }
        if result.accepted { wrongStreak = 0 } else { wrongStreak += 1 }
        if GameHints.isProgress(result.events) {
            movesSinceProgress = 0
            hint = nil
        } else if result.accepted && command.costsMoves {
            movesSinceProgress += 1
        }
        if let showing = hint, result.accepted {
            hint = GameHints.make(state, level: showing.level)
        }
        showHint(asked: false)
        prepareModel()
    }

    private func notUnderstood(_ id: String, words: String) {
        wrongStreak += 1
        message = "Not a command I know: \u{201C}\(words)\u{201D}"
        update(id) {
            $0.outcome = "Not understood."
            $0.accepted = false
        }
        showHint(asked: false)
    }

    private func showHint(asked: Bool) {
        guard let level = GameHints.level(wrongStreak: wrongStreak, movesSinceProgress: movesSinceProgress, asked: asked, showing: hint) else {
            return
        }
        if !asked, let showing = hint, showing.level == level { return }
        hint = GameHints.make(state, level: level)
        if level >= 2 { askModelForClue() }
    }

    private var recentWrongWords: [String] {
        Array(entries.prefix(6).filter { $0.accepted == false }.map(\.words).prefix(3))
    }

    /// The hint engine's model: given a short state, the next step and the words that did not work, it
    /// may phrase the clue through one tool. The code keeps the square and checks the words.
    private func askModelForClue() {
        guard OnDeviceModel.status.isAvailable, !hintAsking, !modelBusy, let code = hint, code.level >= 2,
              state.status == .playing,
              let plan = GamePlanner.plan(state), let next = GamePlanner.compress(plan).first else { return }
        hintAsking = true
        let basis = state
        let prompt = GameHints.modelPrompt(state: basis, next: next, wrong: recentWrongWords)
        let tools = [GameHints.clueTool]
        Task { [weak self] in
            guard let self else { return }
            let turn = await self.engine.ask(role: "hint", instructions: GameHints.modelInstructions, prompt: prompt, tools: tools)
            self.hintAsking = false
            self.hintTurns.insert(turn, at: 0)
            guard let words = GameHints.checkClue(turn.arguments["words"]), self.state == basis, var showing = self.hint else { return }
            showing.words = words
            showing.source = "model"
            self.hint = showing
        }
    }

    private func update(_ id: String, _ change: (inout GameLogEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    // MARK: The model, one request at a time

    func prepareModel() {
        guard mode != .phrases || shadowModel else { return }
        engine.prepare(instructions: GameModelEngine.rulesInstructions, tools: tools)
    }

    private func queueModel(_ pending: Pending) {
        waiting.append(pending)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !self.waiting.isEmpty {
                let next = self.waiting.removeFirst()
                await self.runModel(next)
            }
            self?.worker = nil
        }
    }

    private func runModel(_ pending: Pending) async {
        modelBusy = true
        defer { modelBusy = false }
        let basis = pending.basis ?? state
        let offered = GameToolScope.tools(for: basis)
        let prompt = GameModelEngine.prompt(words: pending.words, state: basis)
        let turn = await engine.ask(role: "rules", instructions: GameModelEngine.rulesInstructions, prompt: prompt, tools: offered)
        update(pending.id) {
            $0.model = turn
            $0.shadow = !pending.act
        }
        guard let tool = turn.tool else {
            if pending.act {
                if let error = turn.error {
                    message = error.words
                    update(pending.id) { $0.outcome = error.words }
                } else {
                    notUnderstood(pending.id, words: pending.words)
                }
            }
            prepareModel()
            return
        }
        switch GameToolScope.check(tool: tool, arguments: turn.arguments, offered: offered) {
        case .ok(let command):
            update(pending.id) { $0.modelCommand = command.words }
            // The state may have moved on while the model thought: the rules judge against now.
            if pending.act { act(command, entryId: pending.id, engine: "model") }
        case .refused(let why):
            update(pending.id) { $0.modelRefusal = why }
            if pending.act {
                wrongStreak += 1
                message = why
                update(pending.id) {
                    $0.outcome = why
                    $0.accepted = false
                }
            }
        }
        prepareModel()
    }

    // MARK: Listening

    /// Goes up on every stop, so that a start still waiting (for permission, or for the speech model)
    /// when it was stopped gives up instead of taking the microphone afterwards.
    private var listenGeneration = 0

    /// Whether a voice note is being recorded: as the owner of recording says through the Lab's host,
    /// or, where it has not said, the recorder's own flag.
    static var noteRecording: Bool { LabActionHost.shared.isRecording?() ?? VoiceRecorder.noteRecording }
    private var starting = false

    /// Why listening cannot start now, or nil. A voice note being recorded owns the microphone.
    nonisolated static func refusal(localeId: String, noteRecording: Bool) -> String? {
        if noteRecording { return "A voice note is being recorded. Finish it first: listening now would take its microphone." }
        if localeId.isEmpty { return "Choose the language spoken in Settings first." }
        return nil
    }

    func startListening(localeId: String) async {
        guard !listening, !starting else { return }
        problem = nil
        if let why = Self.refusal(localeId: localeId, noteRecording: Self.noteRecording) {
            problem = why
            return
        }
        starting = true
        defer { starting = false }
        let mine = listenGeneration
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "The microphone is not allowed for this app."
            return
        }
        // Stopped while asking, or a recording began meanwhile: give up.
        guard mine == listenGeneration, !Self.noteRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Play and record, out of the speaker, so the voice player can be heard by the microphone.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            liveSettled = ""
            liveVolatile = ""
            consumed = 0
            early = nil
            lastVolatileChange = nil
            listening = true
            try await live.start(localeId: localeId) { [weak self] settled, volatile in
                let at = Date()
                Task { @MainActor [weak self] in self?.heardLive(settled: settled, volatile: volatile, at: at) }
            }
            if mine != listenGeneration {
                // A stop overtook this start while the speech model was being readied.
                listening = false
                await live.stop()
            }
        } catch {
            listening = false
            await live.stop()
            problem = "Listening could not start: \(error.localizedDescription)"
        }
    }

    /// Lets go of the microphone. The audio session is left as it is: deactivating it here could cut
    /// off a recording or playback that another part of the app has started since.
    func stopListening() async {
        listenGeneration += 1
        guard listening else { return }
        listening = false
        earlyTask?.cancel()
        earlyTask = nil
        await live.stop()
        let rest = (String(liveSettled.dropFirst(consumed)) + " " + liveVolatile).trimmingCharacters(in: .whitespacesAndNewlines)
        let ended = lastVolatileChange ?? Date()
        if let pendingEarly = early {
            early = nil
            settleEarly(pendingEarly, words: rest, settledAt: Date(), endedAt: ended)
        } else {
            hear(rest, source: "spoken", endedAt: ended)
        }
        liveVolatile = ""
    }

    private func heardLive(settled: String, volatile: String, at: Date) {
        guard listening else { return }
        if volatile != liveVolatile && !volatile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastVolatileChange = at
        }
        liveSettled = settled
        liveVolatile = volatile
        if let piece = LabUtterances.fresh(settled: settled, consumed: consumed) {
            consumed = piece.consumed
            earlyTask?.cancel()
            earlyTask = nil
            let ended = lastVolatileChange ?? at
            lastVolatileChange = nil
            if let pendingEarly = early {
                early = nil
                settleEarly(pendingEarly, words: piece.text, settledAt: at, endedAt: ended)
            } else {
                hear(piece.text, source: "spoken", endedAt: ended, settledAt: at)
            }
            return
        }
        scheduleEarly()
    }

    /// The phrases act on unsettled words once they have held still for a moment.
    private func scheduleEarly() {
        guard actEarly, mode != .model, early == nil else { return }
        earlyTask?.cancel()
        earlyTask = nil
        let words = liveVolatile
        guard let command = GamePhrases.parse(words, kind: state.kind) else { return }
        let endedAt = lastVolatileChange ?? Date()
        earlyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(GameController.earlyPauseMs))
            guard !Task.isCancelled, let self, self.listening, self.early == nil, self.liveVolatile == words else { return }
            if let id = self.hear(words, source: "spoken", endedAt: endedAt, early: true) {
                self.early = (id, command)
            }
        }
    }

    /// The words that were acted on early have settled. The same command: nothing more to do. More of
    /// the same move: the rest of it. Something else: the settled words are a sentence of their own.
    private func settleEarly(_ acted: (id: String, command: GameCommand), words: String, settledAt: Date, endedAt: Date) {
        update(acted.id) { $0.settledAt = settledAt }
        guard let settled = GamePhrases.parse(words, kind: state.kind), settled != acted.command else { return }
        if case .move(let d, let n) = acted.command, case .move(let d2, let m) = settled, d == d2, m > n {
            let id = newEntry(words: words, source: "spoken", endedAt: endedAt, settledAt: settledAt)
            act(.move(d, m - n), entryId: id, engine: "phrases")
            return
        }
        hear(words, source: "spoken", endedAt: endedAt, settledAt: settledAt)
    }

    // MARK: Export

    var log: GameLog {
        GameLog(device: LabDevice(appVersion: AppInfo.versionLine(),
                                  system: ProcessInfo.processInfo.operatingSystemVersionString,
                                  machine: Diagnostics.machineIdentifier(),
                                  modelStatus: OnDeviceModel.status.text,
                                  modelContextSize: OnDeviceModel.contextSize),
                rulesInstructions: GameModelEngine.rulesInstructions,
                assumptions: GameLog.assumptionWords,
                entries: entries,
                hints: hintTurns)
    }

    func clearLog() {
        entries = []
        hintTurns = []
    }
}
