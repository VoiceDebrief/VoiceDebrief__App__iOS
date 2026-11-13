import Foundation

/// Launch arguments for the screenshots (issue 016), read by the UI tests in `UITests/`:
///
///     -VDSampleData full        invented notes and one invented vault, in a temporary folder and in memory
///     -VDSampleData empty       the same, with nothing in them: the empty states
///     -VDScreen note.finished   open that screen directly (see `LaunchScreen` for the ids)
///
/// Debug builds only: in a release build every option reads as absent, and the sample code
/// (`SampleData.swift`, `LaunchSample.swift`) is not compiled at all. `-VDScreen` does nothing
/// without `-VDSampleData`: a screen is only ever opened directly over invented data.
enum LaunchOptions {
    static var arguments: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }

    /// The word after `name`, if both are there.
    static func value(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Which sample set was asked for. Anything other than the two known words is no sample data.
    static func sampleSet(in arguments: [String] = LaunchOptions.arguments) -> SampleSet? {
        value("-VDSampleData", in: arguments).flatMap(SampleSet.init(rawValue:))
    }

    /// The screen to open, honoured only together with sample data. An unknown id opens Record.
    static func screen(in arguments: [String] = LaunchOptions.arguments) -> LaunchScreen? {
        guard sampleSet(in: arguments) != nil else { return nil }
        return value("-VDScreen", in: arguments).flatMap(LaunchScreen.init(rawValue:)) ?? .record
    }
}

enum SampleSet: String, Sendable {
    case full
    case empty
}

/// The four tabs of the shell, so a launch can select one.
enum RootTab: String, Hashable, Sendable {
    case record, library, vaults, settings
}

/// Every screen a UI test can open directly. The raw value is the id used in `-VDScreen` and in
/// the screenshot's file name. `UITests/ScreensTests.swift` has one test per shot.
enum LaunchScreen: String, CaseIterable, Sendable {
    case record
    case recordRecording = "record.recording"
    case recordWorking = "record.working"
    case library
    case noteFinished = "note.finished"
    case noteTranscript = "note.transcript"
    case noteInterrupted = "note.interrupted"
    case noteWorking = "note.working"
    case vaults
    case vaultDetail = "vault.detail"
    case settings
    case diagnostics
    case traffic
    case about

    var tab: RootTab {
        switch self {
        case .record, .recordRecording, .recordWorking: return .record
        case .library, .noteFinished, .noteTranscript, .noteInterrupted, .noteWorking: return .library
        case .vaults, .vaultDetail: return .vaults
        case .settings, .diagnostics, .traffic, .about: return .settings
        }
    }

    /// True for a screen that is reached by a tap from its tab's first screen. It is shown pushed
    /// on a stand-in for that first screen, so the tab bar and the back button are the real ones.
    var isPushed: Bool {
        switch self {
        case .record, .recordRecording, .recordWorking, .library, .vaults, .settings: return false
        default: return true
        }
    }

    /// The accessibility identifier the shell carries when this screen was opened by a launch
    /// argument, so a UI test can tell that the argument was read.
    var marker: String { "vd.screen.\(rawValue)" }
}
