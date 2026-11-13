import AVFoundation
import Observation

/// Plays one note's recording, so that "kept" can be checked by ear (review round 1, issue 029).
/// One player for the screen; it stops when the screen goes.
@MainActor
@Observable
final class NotePlayer {
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var problem: String?
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var ticker: Task<Void, Never>?

    /// Reads the file's length without playing it. A recording that was cut off and repaired still has one.
    func load(_ url: URL) {
        guard url != loadedURL else { return }
        stop()
        loadedURL = url
        do {
            let made = try AVAudioPlayer(contentsOf: url)
            made.prepareToPlay()
            player = made
            duration = made.duration
            problem = nil
        } catch {
            player = nil
            duration = 0
            problem = "This recording cannot be played: \(error.localizedDescription)"
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            tick()
        }
    }

    /// Moves to a moment in the recording and plays from there: a transcript line was tapped.
    func play(fromMs ms: Int) {
        guard let player else { return }
        player.currentTime = min(max(0, Double(ms) / 1000), max(0, player.duration - 0.1))
        position = player.currentTime
        if !player.isPlaying { toggle() }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), player.duration)
        position = player.currentTime
    }

    func stop() {
        ticker?.cancel()
        player?.stop()
        isPlaying = false
        position = 0
    }

    private func tick() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    if player.currentTime == 0 || player.currentTime >= player.duration - 0.05 { self.position = 0 }
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}
