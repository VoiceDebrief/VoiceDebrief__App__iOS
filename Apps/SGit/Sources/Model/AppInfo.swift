import Foundation

/// What the app can say about itself.
enum AppInfo {
    /// "0.1.0 (12)" from the bundle; CI sets the values: the repository's version and the run number.
    static func versionLine(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// "v0.1.42": the version as the release history names it.
    static func shortVersion(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        "v" + (info?["CFBundleShortVersionString"] as? String ?? "0.0.0")
    }

    /// This version's own page of what changed. The two apps share one release history.
    static func notes(for version: String = shortVersion()) -> URL {
        URL(string: "https://ios.app.voicedebrief.ai/versions/\(version)/index.html")!
    }

    /// The project's site, where the sgit app's pages live under sgit-app/.
    static let site = URL(string: "https://ios.app.voicedebrief.ai")!
    static let sgitSite = URL(string: "https://sgit.ai")!
    static let source = URL(string: "https://github.com/VoiceDebrief/VoiceDebrief__App__iOS")!
    /// The web Vault UI, which opens a vault from a key in the link's fragment.
    static let webVault = "https://vault.sgraph.ai/"
}
