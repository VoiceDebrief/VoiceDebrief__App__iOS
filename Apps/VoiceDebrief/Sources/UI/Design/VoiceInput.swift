import SwiftUI

/// The one microphone every text field shares (the owner, 15 November 2026: "a little voice button
/// everywhere we have an input"). It listens through the Lab's `LabListener`, so it keeps that
/// listener's rules: one at a time, never while a note is being recorded, a start that a stop
/// overtook is given up, the shared audio session is left alone, and it stops when the app leaves
/// the foreground. Starting in another field stops the first.
@MainActor
@Observable
final class FieldDictation {
    static let shared = FieldDictation()

    /// The field that is listening now, if any.
    private(set) var activeField: UUID?
    /// Why the last start did not happen, and in which field.
    private(set) var problem: (field: UUID, text: String)?

    private let listener: LabListener
    private var before = ""
    private var apply: ((String) -> Void)?

    private init() {
        listener = LabListener()
        listener.onWords = { [weak self] settled, volatile in
            guard let self, let apply = self.apply else { return }
            apply(DictationText.join(self.before, settled + volatile))
        }
        listener.onStop = { [weak self] in self?.ended() }
    }

    /// Starts listening into a field, or stops if that field is the one listening.
    func toggle(field: UUID, current: String, apply: @escaping (String) -> Void) async {
        if activeField == field {
            await stop()
            return
        }
        if activeField != nil { await stop() }
        before = current
        self.apply = apply
        activeField = field
        problem = nil
        let localeId = UserDefaults.standard.string(forKey: "vd.localeId") ?? ""
        if let why = await listener.start(localeId: localeId) {
            problem = (field, why)
            ended()
        }
    }

    func stop() async {
        await listener.stop()
        ended()
    }

    /// Stops only if this field is the one listening (a field going off screen).
    func stop(field: UUID) async {
        if activeField == field { await stop() }
    }

    private func ended() {
        activeField = nil
        apply = nil
    }
}

/// A microphone button beside a text field that fills it by speech, on this device: the words
/// appear in the field as they are said, after whatever was typed; tap again to stop; the text
/// stays editable. Not for keys, tokens or links.
struct VoiceInputModifier: ViewModifier {
    @Binding var text: String
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let dictation = FieldDictation.shared
        let on = dictation.activeField == id
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .center, spacing: DS.Space.xs) {
                content
                Button {
                    Task { await dictation.toggle(field: id, current: text) { text = $0 } }
                } label: {
                    Image(systemName: on ? "mic.fill" : "mic")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(on ? DS.Palette.red : Color.secondary)
                        .symbolEffect(.pulse, isActive: on)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(on ? "Stop dictating" : "Dictate")
            }
            if let problem = dictation.problem, problem.field == id {
                Text(problem.text)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.red)
            }
        }
        .onDisappear { Task { await dictation.stop(field: id) } }
    }
}

extension View {
    /// Adds the shared voice button to a text field, filling `text` by speech.
    func voiceInput(_ text: Binding<String>) -> some View {
        modifier(VoiceInputModifier(text: text))
    }
}
