import SwiftUI

/// What you have done in the app, kept on this device, and a button to send it to the developer.
struct ActivityView: View {
    private let log = UsageLog.shared
    @State private var sending = false
    @State private var said: String?

    var body: some View {
        List {
            SectionBannerRow(tab: .activity)
            Section {
                LabeledContent("Last used", value: log.lastUsed?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                LabeledContent("Events kept", value: "\(log.events.count)")
            } footer: {
                Text("Every screen you open and for how long, and the main things you do. Never the words of a note, a name or a key. Kept on this device until you send or clear it.")
            }
            Section("Screens") {
                ForEach(log.screens, id: \.name) { s in
                    LabeledContent(s.name, value: "\(s.count)× · \(Timecode.duration(seconds: s.seconds))")
                }
            }
            Section("Actions") {
                ForEach(log.actions, id: \.name) { a in
                    LabeledContent(a.name, value: "\(a.count)×")
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
                Text("Encrypted on this device to the developer's key, like a note.")
            }
        }
        .readableWidth()
        .navigationTitle("Your activity")
    }

    private func send() async {
        guard let lane = DeveloperLane.builtIn else { return }
        sending = true
        defer { sending = false }
        do {
            let body = try log.report(app: AppInfo.versionLine(), device: Diagnostics.machineIdentifier())
            let header = DeveloperLane.Header(kind: "voicedebrief/usage/v1", note: "usage-\(Int(Date().timeIntervalSince1970))", part: 1, of: 1,
                                              name: "usage.json", size: body.count, sha256: DeveloperLane.sha256Hex(body),
                                              app: AppInfo.versionLine(), sentAt: ISO8601DateFormatter().string(from: Date()))
            try await lane.send([try DeveloperLane.message(header: header, body: body)]) { _, _ in }
            said = "Sent \(log.events.count) events."
            UsageLog.shared.action("activity.send")
        } catch {
            said = "Not sent: \(error.localizedDescription)"
        }
    }
}
