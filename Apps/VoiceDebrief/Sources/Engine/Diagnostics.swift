import Foundation

/// What this device reports about Apple's models, and how the last run went. Exported as JSON so
/// that a run on a real device leaves evidence that can be read later.
struct Diagnostics: Codable, Equatable, Sendable {
    var appVersion: String
    var system: String
    var machine: String
    var preferredLanguages: [String]
    var speechAvailable: Bool
    var speechSupportedLocales: [String]
    var speechInstalledLocales: [String]
    var modelStatus: String
    var modelContextSize: Int?
    var modelLanguages: [String]
    var lastRun: DebriefRun?

    static func gather(lastRun: DebriefRun?) async -> Diagnostics {
        Diagnostics(
            appVersion: AppInfo.versionLine(),
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            machine: machineIdentifier(),
            preferredLanguages: Locale.preferredLanguages,
            speechAvailable: SpeechFileTranscriber.isAvailable,
            speechSupportedLocales: await SpeechFileTranscriber.supportedLocaleIds(),
            speechInstalledLocales: await SpeechFileTranscriber.installedLocaleIds(),
            modelStatus: OnDeviceModel.status.text,
            modelContextSize: OnDeviceModel.contextSize,
            modelLanguages: OnDeviceModel.supportedLanguageIds,
            lastRun: lastRun.map(Diagnostics.withoutContent))
    }

    /// A run with its words removed: the export says how the run went, not what was said.
    static func withoutContent(_ run: DebriefRun) -> DebriefRun {
        var copy = run
        if let transcript = run.transcript {
            copy.transcript = Transcript(localeId: transcript.localeId, lines: transcript.lines.map {
                TranscriptLine(startMs: $0.startMs, endMs: $0.endMs, text: "(\($0.text.count) characters)")
            })
        }
        if let debrief = run.debrief { copy.debrief = "(\(debrief.count) characters)" }
        copy.source = run.source == "Recorded here" ? run.source : "Imported file"
        return copy
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// "iPhone17,1" and the like.
    static func machineIdentifier() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}
