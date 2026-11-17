import SwiftUI

/// The share sheet: the file's name and length, "Debrief in VoiceDebrief" and Cancel.
struct ShareSheetView: View {
    let model: ShareModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch model.state {
                case .loading:
                    ProgressView("Reading the voice note")
                case .ready:
                    ready
                case .kept:
                    kept
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Close") { model.cancel() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("VoiceDebrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.state != .kept {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                }
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(model.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text([model.lengthText, model.sizeText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                model.keep()
            } label: {
                Text("Debrief in VoiceDebrief")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Transcribed and debriefed on this device, with Apple's models, the next time VoiceDebrief is open.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var kept: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Kept")
                .font(.headline)
            Text("Open VoiceDebrief: the note will be in the library, with its transcript and debrief.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { model.done() }
                .buttonStyle(.borderedProminent)
        }
    }
}
