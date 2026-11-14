import AVFoundation
import Foundation
import Observation

/// What the voice player says next: the next stretch of the planner's way, in words that vary, and now
/// and then something wrong, so that the hint engine has something to see. Plain code, unit tested.
enum GamePlayerScript {
    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    /// How often a mistake is made: on every turn whose number leaves this remainder by seven.
    static let mistakeTurn = 5

    static func line(for state: GameState, turn: Int, mistakes: Bool) -> String? {
        switch state.status {
        case .levelWon: return "next level"
        case .won: return nil
        case .lost: return "restart"
        case .playing: break
        }
        if mistakes && turn % 7 == mistakeTurn, let wrong = mistake(for: state, turn: turn) { return wrong }
        guard let plan = GamePlanner.plan(state), let next = GamePlanner.compress(plan).first else { return "restart" }
        return words(for: next, turn: turn)
    }

    static func words(for command: GameCommand, turn: Int) -> String {
        switch command {
        case .move(let direction, let steps):
            let d = direction.rawValue
            if steps == 1 { return ["\(d)", "go \(d)", "move \(d)", "step \(d)"][turn % 4] }
            let n = numberWords[min(steps, 9)]
            return ["go \(d) \(n)", "\(d) \(n)", "move \(d) \(n) squares"][turn % 3]
        case .jump(let direction):
            return direction.map { ["jump \($0.rawValue)", "jump to the \($0.rawValue)"][turn % 2] } ?? "jump"
        case .climb(let direction, let steps):
            return steps == 1 ? "climb \(direction.rawValue)" : "climb \(direction.rawValue) \(numberWords[min(steps, 9)])"
        case .unlock: return ["unlock the door", "open the door"][turn % 2]
        default: return command.words
        }
    }

    /// A direction that is blocked, or words no engine knows.
    static func mistake(for state: GameState, turn: Int) -> String? {
        let blocked = GameDirection.allCases.first { state.tile(at: state.player.moved($0)).isSolid }
        if turn % 2 == 0, let blocked { return "go \(blocked.rawValue)" }
        return "fly over the wall"
    }
}

/// Hands the end of an utterance back from the synthesiser's thread, once.
final class GameSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: (@Sendable (Date) -> Void)?

    func wait(_ done: @escaping @Sendable (Date) -> Void) {
        lock.lock()
        waiting = done
        lock.unlock()
    }

    private func finish() {
        let at = Date()
        lock.lock()
        let done = waiting
        waiting = nil
        lock.unlock()
        done?(at)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish() }
}

/// The voice player: a synthetic player that says its commands aloud. While the game is listening, the
/// microphone hears them and they go through exactly the same way as the owner's; otherwise its words are
/// handed in directly. It plans in code; it is not a model.
@MainActor
@Observable
final class GameVoicePlayer {
    static let shared = GameVoicePlayer()

    private(set) var playing = false
    private(set) var saying: String?
    private(set) var turns = 0
    var mistakes = true

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = GameSpeechDelegate()
    private var loop: Task<Void, Never>?

    init() {
        synthesizer.delegate = delegate
    }

    func start(_ game: GameController, localeId: String) {
        guard !playing else { return }
        playing = true
        turns = 0
        loop = Task { [weak self] in
            await self?.run(game, localeId: localeId)
        }
    }

    func stop() {
        playing = false
        saying = nil
        loop?.cancel()
        loop = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func run(_ game: GameController, localeId: String) async {
        if !game.listening && !GameController.noteRecording {
            // Heard or not, the speech must come out of the speaker.
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        while playing && !Task.isCancelled {
            guard let line = GamePlayerScript.line(for: game.state, turn: turns, mistakes: mistakes) else { break }
            turns += 1
            saying = line
            let before = game.entries.count
            game.playerStarted()
            let finished = await speak(line, localeId: localeId)
            guard playing && !Task.isCancelled else { break }
            game.playerFinished(at: finished)
            if !game.listening {
                game.hear(line, source: "player", endedAt: finished)
            }
            // Wait for the game to answer: the sentence logged and acted on, or a few seconds.
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline && !Task.isCancelled {
                if game.entries.count > before, let newest = game.entries.first, newest.outcome != nil, !game.modelBusy { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        playing = false
        saying = nil
    }

    private func speak(_ line: String, localeId: String) async -> Date {
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = AVSpeechSynthesisVoice(language: localeId.isEmpty ? "en-GB" : localeId.replacingOccurrences(of: "_", with: "-"))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return await withCheckedContinuation { continuation in
            delegate.wait { at in continuation.resume(returning: at) }
            synthesizer.speak(utterance)
        }
    }
}
