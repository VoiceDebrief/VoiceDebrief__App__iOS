import Foundation

/// Finishing a note saves it to a vault, without a button to remember (issue 022). On by default;
/// does nothing until there is a vault that can be written to. The note is already safe on the
/// device, so a save that fails is recorded on the note and never loses anything.
@MainActor
enum AutoSave {
    static let switchKey = "vd.autoSave"
    static let vaultKey = "vd.saveVault"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: switchKey) == nil ? true : UserDefaults.standard.bool(forKey: switchKey)
    }

    static func run(noteId: String, store: NoteStore, book: VaultBook) async {
        guard isOn, let note = store.note(noteId), !note.processing,
              let transcript = note.run.transcript, !transcript.isEmpty else { return }
        let writable = book.vaults.filter(\.canWrite)
        let chosen = UserDefaults.standard.string(forKey: vaultKey) ?? ""
        guard let vault = writable.first(where: { $0.id == chosen }) ?? writable.first else { return }
        do {
            _ = try await book.save(run: note.run, audioURL: store.audioURL(for: noteId), to: vault)
            store.recordSave(noteId, save: NoteSave(vaultId: vault.id, vaultName: vault.name, at: Date()), problem: nil)
        } catch {
            store.recordSave(noteId, save: nil, problem: VaultBook.describe(error))
        }
    }
}
