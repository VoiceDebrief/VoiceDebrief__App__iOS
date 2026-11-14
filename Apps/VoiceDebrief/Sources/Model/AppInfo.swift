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

    /// True when `other` ("0.1.90") is a later version than `mine` ("0.1.82"), compared number by number.
    static func isNewer(_ other: String, than mine: String) -> Bool {
        let a = other.split(separator: ".").map { Int($0) ?? 0 }, b = mine.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The version alone, "0.1.82".
    static func version(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Opens the TestFlight app, where an update is installed.
    static let testFlight = URL(string: "itms-beta://")!

    /// The release history on the project's site.
    static let releaseNotes = URL(string: "https://ios.app.voicedebrief.ai/versions/index.html")!

    /// "v0.1.27": the version alone, as the badge at the top shows it.
    static func shortVersion(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        "v" + (info?["CFBundleShortVersionString"] as? String ?? "0.0.0")
    }

    /// This version's own page of what changed, with pictures; the release history until it exists.
    static func notes(for version: String = shortVersion()) -> URL {
        URL(string: "https://ios.app.voicedebrief.ai/versions/\(version)/index.html")!
    }

    /// The site whose passkey opens the account: the register of people at pki.sgit.ai.
    static let passkeySite = VaultDoor.pkiSite

    static let site = URL(string: "https://ios.app.voicedebrief.ai")!
    static let source = URL(string: "https://github.com/VoiceDebrief/VoiceDebrief__App__iOS")!
}
