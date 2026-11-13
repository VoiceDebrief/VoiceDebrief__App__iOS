import SwiftUI

/// The only screen of this build: what the app is, what is built and what is not.
struct StatusView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice note in, transcript and debrief out, on this device.")
                            .font(.title3.weight(.semibold))
                        Text("This is an early build. It does not transcribe anything yet: it exists so that every later step arrives in an app that already builds, tests and installs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("In this build") {
                    ForEach(Roadmap.stages(.built)) { stage in
                        StageRow(stage: stage)
                    }
                }

                Section("Not built yet") {
                    ForEach(Roadmap.stages(.proposed)) { stage in
                        StageRow(stage: stage)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.versionLine())
                    LabeledContent("Passkey site", value: AppInfo.passkeySite)
                    Link("The plan and what is built", destination: AppInfo.site)
                    Link("Source code", destination: AppInfo.source)
                }
            }
            .navigationTitle("VoiceDebrief")
        }
    }
}

struct StageRow: View {
    let stage: Stage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
                Text(stage.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stage.status == .built ? Color.accentColor : Color.secondary)
            }
            Text(stage.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StatusView()
}
