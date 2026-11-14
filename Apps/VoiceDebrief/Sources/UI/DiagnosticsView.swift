import SwiftUI

/// What this device reports about Apple's models. This is the evidence for the plan's quality
/// spike: which languages exist, whether the model is there, how long each step took.
struct DiagnosticsView: View {
    let session: DebriefSession
    @State private var report: Diagnostics?

    var body: some View {
        Group {
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
                if let lane = DeveloperLane.builtIn {
                    Section {
                        LabeledContent("Vault", value: lane.vault)
                        LabeledContent("Key", value: lane.fingerprint)
                    } header: {
                        Text("The developer's lane in this test build")
                    } footer: {
                        Text("Where \"Send to the developer\" goes: an inbox only the developer's key opens. It cannot be changed here. To send to someone else, add them under Settings, Recipients.")
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Diagnostics")
            .task(id: session.run) { report = await Diagnostics.gather(lastRun: session.run) }
        }
    }

    private func list(_ items: [String]) -> String {
        items.isEmpty ? "None" : items.joined(separator: ", ")
    }
}
