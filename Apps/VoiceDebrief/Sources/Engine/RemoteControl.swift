import MediaPlayer

/// While recording, the play/pause button on headphones, AirPods, a car's steering wheel or the lock
/// screen finishes the recording. Untried: iOS sends these commands to the app it treats as playing
/// audio, and a recording app may not qualify.
@MainActor
enum RemoteControl {
    private static var targets: [Any] = []

    static func begin(title: String, onFinish: @escaping @MainActor () -> Void) {
        end()
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.pauseCommand, center.stopCommand] {
            command.isEnabled = true
            targets.append(command.addTarget { _ in
                Task { @MainActor in onFinish() }
                return .success
            })
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "VoiceDebrief",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    static func end() {
        let center = MPRemoteCommandCenter.shared()
        for target in targets {
            center.togglePlayPauseCommand.removeTarget(target)
            center.pauseCommand.removeTarget(target)
            center.stopCommand.removeTarget(target)
        }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
