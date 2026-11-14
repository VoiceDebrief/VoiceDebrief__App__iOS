import SwiftUI

/// What you have done in the app, kept on this device, and a button to send it to the developer.
/// After VoiceDebrief's `ActivityView`; the report has the same shape, with the kind `sgit/usage/v1`.
struct ActivityView: View {
    private let log = UsageLog.shared
    @State private var sending = false
    @State private var said: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Last used", value: log.lastUsed?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                LabeledContent("Events kept", value: "\(log.events.count)")
                LabeledContent("This install", value: "\(UsageLog.machineIdentifier()) \(UsageLog.installId)")
            } footer: {
                Text("Every screen you open and for how long, and every action you take. Never the name of a file or a vault, and never a key. Kept on this device until you send or clear it. Each device keeps its own: send from each to give the whole picture.")
            }
            Section("Screens") {
                ForEach(log.screens, id: \.name) { screen in
                    LabeledContent(screen.name, value: "\(screen.count)× · \(Self.duration(screen.seconds))")
                }
            }
            Section("Actions") {
                ForEach(log.actions, id: \.name) { action in
                    LabeledContent(action.name, value: "\(action.count)×")
                }
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "Sending" : "Send this to Claude (developer)", systemImage: "paperplane")
                }
                .disabled(sending || log.events.isEmpty || DeveloperLane.builtIn == nil)
                if let said { Text(said).font(.footnote).foregroundStyle(.secondary) }
                Button("Clear", role: .destructive) { log.clear() }
            } footer: {
                Text("Encrypted on this device to the developer's key and left on \(DeveloperLane.endpoint.host() ?? "the server"), which cannot read it.")
            }
        }
        .navigationTitle("Your activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "45 s", "3 min 05 s", "1 h 02 min".
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        if total < 3_600 { return "\(total / 60) min \(String(format: "%02d", total % 60)) s" }
        return "\(total / 3_600) h \(String(format: "%02d", (total % 3_600) / 60)) min"
    }

    private func send() async {
        guard let lane = DeveloperLane.builtIn else { return }
        sending = true
        defer { sending = false }
        do {
            let count = log.events.count
            try await lane.send([try log.laneMessage(app: "sgit " + AppInfo.versionLine())]) { _, _ in }
            said = "Sent \(count) events."
            log.action("activity.send")
        } catch {
            said = "Not sent: \(error.localizedDescription)"
        }
    }
}
