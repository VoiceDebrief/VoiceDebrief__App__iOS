import Foundation
import Observation

/// The library: every note on this device, one folder each, holding `note.json` and the audio.
/// A note is written the moment a recording stops, before anything else is done with it, so a
/// crash, a model that fails or closing the app cannot lose it.
@MainActor
@Observable
final class NoteStore {
    let root: URL
    private(set) var notes: [Note] = []
    private(set) var problem: String?

    /// The folder for the real library: Application Support, not a cache, so the system does not clear it.
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "notes", directoryHint: .isDirectory)
    }

    init(root: URL = NoteStore.defaultRoot) {
        self.root = root
        load()
    }

    private func folder(_ id: String) -> URL { root.appending(path: id, directoryHint: .isDirectory) }
    private func file(_ id: String) -> URL { folder(id).appending(path: "note.json") }

    private func load() {
        let manager = FileManager.default
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [Note] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: "note.json")),
                  let note = try? decoder.decode(Note.self, from: data) else { continue }
            found.append(note)
        }
        notes = found.sorted { $0.createdAt > $1.createdAt }
        // A note still marked as in progress was cut off: the app closed or died while it was being
        // recorded or processed. If its recording was never closed, make it readable again.
        for note in notes where note.processing {
            if let name = note.audioName, name.hasSuffix(".wav") {
                WAVRepair.repair(fileAt: folder(note.id).appending(path: name))
            }
        }
    }

    private func write(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: folder(note.id), withIntermediateDirectories: true)
            try encoder.encode(note).write(to: file(note.id), options: .atomic)
            problem = nil
        } catch {
            problem = "This note could not be written to the device: \(error.localizedDescription)"
        }
    }

    /// A new note from an audio file, which is moved into the note's folder. Returns nil, and says
    /// why in `problem`, if the audio could not be kept.
    func create(audioAt url: URL, source: String, localeId: String, now: Date = Date()) -> Note? {
        let id = Note.newId(at: now)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let audioName = "audio.\(ext)"
        do {
            try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: folder(id).appending(path: audioName))
        } catch {
            problem = "The recording could not be kept: \(error.localizedDescription)"
            return nil
        }
        let note = Note(id: id, createdAt: now, run: DebriefRun(source: source, localeId: localeId),
                        audioName: audioName, processing: true)
        write(note)
        notes.insert(note, at: 0)
        return note
    }

    /// A new note for a recording that is about to start, and the file to record into. The note is
    /// in the library before a single sample exists, so nothing that happens next can leave a
    /// recording without a note.
    func begin(source: String, localeId: String, now: Date = Date()) -> (note: Note, audio: URL)? {
        let id = Note.newId(at: now)
        let audioName = "audio.wav"
        do {
            try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        } catch {
            problem = "A place for the recording could not be made: \(error.localizedDescription)"
            return nil
        }
        let note = Note(id: id, createdAt: now, run: DebriefRun(source: source, localeId: localeId),
                        audioName: audioName, processing: true)
        write(note)
        notes.insert(note, at: 0)
        return (note, folder(id).appending(path: audioName))
    }

    /// Swaps a finished note's audio for a compressed copy already written into its folder.
    func replaceAudio(_ id: String, with name: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), let old = notes[index].audioName, old != name else { return }
        notes[index].audioName = name
        write(notes[index])
        try? FileManager.default.removeItem(at: folder(id).appending(path: old))
    }

    func folderURL(for id: String) -> URL { folder(id) }

    func note(_ id: String) -> Note? { notes.first { $0.id == id } }

    /// Replaces a note's run and whether it is still being processed, and writes it.
    func update(_ id: String, run: DebriefRun, processing: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].run.transcript != run.transcript { notes[index].clean = nil }   // made from the old words
        notes[index].run = run
        notes[index].processing = processing
        write(notes[index])
    }

    /// Sets or clears a note's clean text, and writes it.
    func setClean(_ id: String, _ clean: CleanText?) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].clean = clean
        write(notes[index])
    }

    func audioURL(for id: String) -> URL? {
        guard let name = note(id)?.audioName else { return nil }
        let url = folder(id).appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Removes a note and its audio from this device. A copy saved to a vault is not touched.
    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: folder(id))
        notes.removeAll { $0.id == id }
    }
}

extension Note {
    /// Sorts by time and does not collide: "20261113-160501-ab12cd".
    static func newId(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date) + "-" + UUID().uuidString.lowercased().prefix(6)
    }
}
