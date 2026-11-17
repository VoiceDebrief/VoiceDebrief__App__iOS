import Foundation

/// The app's side of the share sheet: it looks in the share inbox when it opens, each time it becomes
/// active, and when the extension says a parcel is complete (a Darwin notification, which reaches the app
/// only while it is running), and turns what is waiting into notes (`DebriefSession.takeShared`).
@MainActor
final class ShareIntake {
    static let shared = ShareIntake()

    private var session: DebriefSession?
    private var listening = false

    /// Starts watching for the extension, and takes what is already waiting.
    func start(session: DebriefSession) {
        self.session = session
        if !listening {
            listening = true
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in Task { @MainActor in ShareIntake.shared.takeWaiting() } },
                ShareInbox.darwinNotification as CFString, nil, .deliverImmediately)
        }
        takeWaiting()
    }

    /// Takes every waiting parcel into the library. Does nothing in a build without the App Group.
    func takeWaiting() {
        guard let session, let inbox = ShareInbox.shared(), !inbox.waiting().isEmpty else { return }
        Task { @MainActor in
            let localeId = await Self.localeId()
            session.takeShared(from: inbox, localeId: localeId)
        }
    }

    /// The language chosen on the Record screen, or else the one closest to the device's.
    static func localeId() async -> String {
        let chosen = UserDefaults.standard.string(forKey: "vd.localeId") ?? ""
        if !chosen.isEmpty { return chosen }
        return await SpeechFileTranscriber.defaultLocaleId() ?? Locale.current.identifier(.bcp47)
    }
}
