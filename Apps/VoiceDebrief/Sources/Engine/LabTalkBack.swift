import AVFoundation
import Foundation
import Observation
import UIKit

/// Says an answer aloud with the system's own voice, and reports how long it took. It does not
/// speak while a note is being recorded: speaking changes the audio session, which is the recording's.
@MainActor
final class LabSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let host: LabActionHost
    private let synthesizer = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?

    init(host: LabActionHost? = nil) {
        self.host = host ?? LabActionHost.shared
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the text and returns how long it took in milliseconds, or nil if it was not spoken.
    func speak(_ text: String, localeId: String) async -> Double? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, host.isRecording?() != true, done == nil else { return nil }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: words)
        if !localeId.isEmpty, let voice = AVSpeechSynthesisVoice(language: localeId) { utterance.voice = voice }
        let clock = ContinuousClock()
        let start = clock.now
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            done = continuation
            synthesizer.speak(utterance)
        }
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// Stops in the middle of a sentence.
    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish() {
        done?.resume()
        done = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish() }
    }
}

/// Experiment L05, talk back: a conversation by voice about the app's own data. The code owns the
/// state, and there are four: idle, listening, thinking, speaking. It listens, takes one settled
/// sentence as a question, stops listening, has the question answered (as L06 does), says the
/// answer, and listens again. It never listens while it speaks, so it does not hear itself.
@MainActor
@Observable
final class LabTalkBack {
    static let shared = LabTalkBack()

    enum State: String, Sendable {
        case idle
        case listening
        case thinking
        case speaking

        var words: String {
            switch self {
            case .idle: return "Not listening"
            case .listening: return "Listening for a question"
            case .thinking: return "Working out the answer"
            case .speaking: return "Saying the answer"
            }
        }
    }

    let desk: LabAskDesk
    private(set) var state = State.idle
    private(set) var running = false
    private(set) var settled = ""
    private(set) var volatile = ""
    private(set) var problem: String?
    var speakAnswers = true

    private let listener: LabListener
    private let speaker: LabSpeaker
    private var localeId = ""
    private var consumed = 0
    /// Goes up on every stop, so a turn that was under way when the conversation was stopped says nothing.
    private var epoch = 0

    init(desk: LabAskDesk? = nil, host: LabActionHost? = nil) {
        self.desk = desk ?? LabAskDesk.talk
        listener = LabListener(host: host)
        speaker = LabSpeaker(host: host)
        listener.onWords = { [weak self] settled, volatile in self?.heard(settled: settled, volatile: volatile) }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.stop() }
        }
    }

    func start(localeId: String) async {
        guard !running else { return }
        self.localeId = localeId
        running = true
        await listen()
        if state != .listening { running = false }
    }

    func stop() async {
        running = false
        epoch += 1
        speaker.stop()
        await listener.stop()
        state = .idle
    }

    private func listen() async {
        settled = ""
        volatile = ""
        consumed = 0
        problem = await listener.start(localeId: localeId)
        state = listener.listening ? .listening : .idle
    }

    private func heard(settled: String, volatile: String) {
        guard state == .listening else { return }
        self.settled = settled
        self.volatile = volatile
        guard let piece = LabUtterances.fresh(settled: settled, consumed: consumed) else { return }
        consumed = piece.consumed
        // One word alone is more likely a cough than a question.
        guard LabTriggerMatcher.words(piece.text).count >= 2 else { return }
        Task { await answer(piece.text, source: "spoken") }
    }

    /// A question typed in place of speech.
    func type(_ question: String) async {
        await answer(question, source: "typed")
    }

    /// One turn: stop listening, answer, say it, listen again if the conversation is still on.
    private func answer(_ question: String, source: String) async {
        guard state == .listening || state == .idle else { return }
        let wasListening = state == .listening
        let mine = epoch
        state = .thinking
        if wasListening { await listener.stop() }
        if let turn = await desk.ask(question, source: source), mine == epoch {
            state = .speaking
            if speakAnswers, let ms = await speaker.speak(turn.spoken, localeId: localeId) {
                desk.spoke(turn.number, ms: ms)
            }
        }
        if running, mine == epoch {
            await listen()
            if state != .listening { running = false }
        } else {
            state = .idle
        }
    }
}
