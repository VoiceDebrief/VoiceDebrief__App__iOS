import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Notes")
@MainActor
struct NoteStoreTests {
    static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "notes-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    static func audioFile(_ bytes: [UInt8] = [1, 2, 3, 4]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString).m4a")
        try Data(bytes).write(to: url)
        return url
    }

    @Test func aNoteIsKeptTheMomentItIsCreated() throws {
        let root = Self.temporaryRoot()
        let store = NoteStore(root: root)
        #expect(store.notes.isEmpty)
        let audio = try Self.audioFile()
        let note = try #require(store.create(audioAt: audio, source: "Recorded here", localeId: "en-GB"))
        #expect(note.processing)
        #expect(store.notes.map(\.id) == [note.id])
        // The audio moved into the note's folder, and a second store finds the note on disk.
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        let kept = try #require(store.audioURL(for: note.id))
        #expect(try Data(contentsOf: kept) == Data([1, 2, 3, 4]))
        let reopened = NoteStore(root: root)
        #expect(reopened.notes.map(\.id) == [note.id])
        #expect(reopened.notes.first?.processing == true)
    }

    @Test func updatesAreWrittenAndSurviveAReopen() throws {
        let root = Self.temporaryRoot()
        let store = NoteStore(root: root)
        let note = try #require(store.create(audioAt: try Self.audioFile(), source: "note.m4a", localeId: "en-GB"))
        var run = note.run
        run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 900, text: "Hello there.")])
        run.debrief = "## Key points\n- Hello.\n\n## Actions\n- none mentioned\n\n## In one sentence\nA greeting.\n"
        store.update(note.id, run: run, processing: false)
        let reopened = NoteStore(root: root)
        let found = try #require(reopened.note(note.id))
        #expect(found.run == run)
        #expect(!found.processing)
        #expect(found.title == "A greeting.")
        #expect(found.stateLine == "On this device")
    }

    @Test func deletingRemovesTheNoteAndItsAudio() throws {
        let root = Self.temporaryRoot()
        let store = NoteStore(root: root)
        let note = try #require(store.create(audioAt: try Self.audioFile(), source: "x", localeId: "en-GB"))
        store.delete(note.id)
        #expect(store.notes.isEmpty)
        #expect(store.audioURL(for: note.id) == nil)
        #expect(NoteStore(root: root).notes.isEmpty)
    }

    @Test func newestFirstAndIdsDoNotCollide() throws {
        let store = NoteStore(root: Self.temporaryRoot())
        let first = try #require(store.create(audioAt: try Self.audioFile(), source: "a", localeId: "en-GB", now: Date(timeIntervalSince1970: 1_000)))
        let second = try #require(store.create(audioAt: try Self.audioFile(), source: "b", localeId: "en-GB", now: Date(timeIntervalSince1970: 1_000)))
        #expect(first.id != second.id)
        #expect(first.id.hasPrefix("19700101-001640-"))
    }
}

@Suite("Note titles and grouping")
struct NoteTitleTests {
    static func note(_ id: String, at seconds: TimeInterval, debrief: String? = nil, first: String? = nil, processing: Bool = false) -> Note {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        if let first { run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 1, text: first)]) }
        run.debrief = debrief
        return Note(id: id, createdAt: Date(timeIntervalSince1970: seconds), run: run, audioName: "audio.m4a", processing: processing)
    }

    @Test func theTitleIsTheOneSentenceThenTheFirstWordsThenAFallback() {
        let debrief = "## Key points\n- a\n\n## Actions\n- none mentioned\n\n## In one sentence\n**Testing** the workflow.\n"
        #expect(Self.note("a", at: 0, debrief: debrief, first: "Okay so this is now").title == "Testing the workflow.")
        #expect(Self.note("b", at: 0, debrief: "no headings here", first: "Okay so this is now").title == "Okay so this is now")
        #expect(Self.note("c", at: 0).title == "Voice note with no words found")
        #expect(Self.note("e", at: 0, processing: true).title == "Voice note, not yet transcribed")
        let long = (1...20).map { "w\($0)" }.joined(separator: " ")
        #expect(Self.note("d", at: 0, first: long).title.split(separator: " ").count == 12)
        #expect(Self.note("d", at: 0, first: long).title.hasSuffix("…"))
    }

    @Test func aSentenceIsNotTakenFromTheNextSection() {
        #expect(Note.oneSentence(in: "## In one sentence\n\n## Actions\n- x") == nil)
        #expect(Note.oneSentence(in: "## In one sentence\n- A bullet.") == "A bullet.")
        #expect(Note.oneSentence(in: "nothing") == nil)
    }

    @Test func theStateIsSaidInWords() {
        #expect(Self.note("a", at: 0, processing: true).stateLine == "Interrupted: open it to run it again")
        #expect(Self.note("b", at: 0).stateLine == "No words found")
        #expect(Self.note("c", at: 0, first: "Hello").stateLine == "Transcript only")
        #expect(Self.note("d", at: 0, debrief: "x", first: "Hello").stateLine == "On this device")
    }

    @Test func notesAreGroupedByDayNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 10 * 86_400 + 3_600)          // day 10, 01:00
        let notes = [
            Self.note("old", at: 7 * 86_400 + 100),
            Self.note("today-early", at: 10 * 86_400 + 60),
            Self.note("yesterday", at: 9 * 86_400 + 500),
            Self.note("today-late", at: 10 * 86_400 + 3_000),
        ]
        let groups = NoteGrouping.byDay(notes, now: now, calendar: calendar)
        #expect(groups.map(\.label).prefix(2) == ["Today", "Yesterday"])
        #expect(groups.count == 3)
        #expect(groups[0].notes.map(\.id) == ["today-late", "today-early"])
        #expect(groups[2].notes.map(\.id) == ["old"])
    }

    @Test @MainActor func aSaveIntoAVaultIsRememberedOnTheNote() throws {
        let root = NoteStoreTests.temporaryRoot()
        let store = NoteStore(root: root)
        let note = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB"))
        store.recordSave(note.id, save: nil, problem: "No network")
        #expect(store.note(note.id)?.saveProblem == "No network")
        store.recordSave(note.id, save: NoteSave(vaultId: "abcd1234", vaultName: "Notes", at: Date(timeIntervalSince1970: 0)), problem: nil)
        let reopened = try #require(NoteStore(root: root).note(note.id))
        #expect(reopened.saves?.map(\.vaultName) == ["Notes"])
        #expect(reopened.saveProblem == nil)
    }
}

@Suite("Who a note was sent to")
@MainActor
struct NoteSendTests {
    @Test func aSendIsRememberedOnTheNoteAndSurvivesAReopen() throws {
        let root = NoteStoreTests.temporaryRoot()
        let store = NoteStore(root: root)
        let note = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB"))
        store.recordSend(note.id, to: "Maria", at: Date(timeIntervalSince1970: 0))
        store.recordSend(note.id, to: "Indi", at: Date(timeIntervalSince1970: 60))
        let reopened = try #require(NoteStore(root: root).note(note.id))
        #expect(reopened.sends?.map(\.to) == ["Maria", "Indi"])
    }
}
