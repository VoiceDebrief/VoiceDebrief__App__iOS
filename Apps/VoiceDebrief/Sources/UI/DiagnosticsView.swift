import SwiftUI

/// What this device reports about Apple's models. This is the evidence for the plan's quality
/// spike: which languages exist, whether the model is there, how long each step took.
struct DiagnosticsView: View {
    let session: DebriefSession
    @State private var report: Diagnostics?
    @AppStorage("vd.developerLane") private var laneLink = ""

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section("This device") {
                        LabeledContent("App", value: report.appVersion)
                        LabeledContent("System", value: report.system)
                        LabeledContent("Machine", value: report.machine)
                    }
                    Section("Apple's speech model") {
                        LabeledContent("Available", value: report.speechAvailable ? "Yes" : "No")
                        LabeledContent("Languages", value: "\(report.speechSupportedLocales.count)")
                        LabeledContent("Portuguese", value: list(report.speechSupportedLocales.filter { $0.hasPrefix("pt") }))
                        LabeledContent("English", value: list(report.speechSupportedLocales.filter { $0.hasPrefix("en") }))
                        LabeledContent("On this device now", value: list(report.speechInstalledLocales))
                    }
                    Section("Apple's language model") {
                        LabeledContent("Status", value: report.modelStatus)
                        LabeledContent("Context", value: report.modelContextSize.map { "\($0) tokens" } ?? "Not known")
                        LabeledContent("Languages", value: list(report.modelLanguages))
                    }
                    Section {
                        ShareLink(item: report.json) {
                            Label("Share this report", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text("The report holds the facts above and how the last run went: timings and sizes, never the words of a transcript or debrief.")
                    }
                } else {
                    ProgressView()
                }
                Section {
                    TextField("sgi1. lane link", text: $laneLink, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let lane = DeveloperLane.parse(laneLink) {
                        LabeledContent("Vault", value: lane.vault)
                        LabeledContent("Key", value: lane.fingerprint)
                        Button("Remove the lane", role: .destructive) { laneLink = "" }
                    } else if !laneLink.isEmpty {
                        Text("That is not a lane link.").font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Developer lane")
                } footer: {
                    Text("Optional. With a lane link here, a button appears after each run to send that note, encrypted, to the developer. Nothing is sent without pressing it. Check the key above matches the one the developer gave you.")
                }
            }
            .navigationTitle("Diagnostics")
            .task(id: session.run) { report = await Diagnostics.gather(lastRun: session.run) }
        }
    }

    private func list(_ items: [String]) -> String {
        items.isEmpty ? "None" : items.joined(separator: ", ")
    }
}
