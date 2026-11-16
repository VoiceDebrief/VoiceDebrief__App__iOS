import Foundation

/// The build's own facts, read from its Info.plist (CI sets the version and the build number).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "ai.sgit.crm.app" }

    static var versionLine: String { "\(version) (\(build))" }
}
