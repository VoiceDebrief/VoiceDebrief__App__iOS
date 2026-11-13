import Foundation
import SGitVault

/// What the app can say about itself.
enum AppInfo {
    /// "0.1.0 (12)" from the bundle; the values are set by CI from the repository's version file.
    static func versionLine(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// The site whose passkey opens the account: the register of people at pki.sgit.ai.
    static let passkeySite = VaultDoor.pkiSite

    static let site = URL(string: "https://ios.app.voicedebrief.ai")!
    static let source = URL(string: "https://github.com/VoiceDebrief/VoiceDebrief__App__iOS")!
}
