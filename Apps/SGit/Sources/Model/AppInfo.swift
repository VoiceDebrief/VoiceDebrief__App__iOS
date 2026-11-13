import Foundation

/// What the app can say about itself.
enum AppInfo {
    /// "0.1.0 (12)" from the bundle; CI sets the values: the repository's version and the run number.
    static func versionLine(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    static let sgitSite = URL(string: "https://sgit.ai")!
    static let source = URL(string: "https://github.com/VoiceDebrief/VoiceDebrief__App__iOS")!
    /// The web Vault UI, which opens a vault from a key in the link's fragment.
    static let webVault = "https://vault.sgraph.ai/"
}
