import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Recording safety")
struct WAVRepairTests {
    /// A WAV header as a recorder leaves it before closing: sizes still zero. `filler` adds a chunk
    /// before the data chunk, as Apple's recorder does.
    static func header(filler: Int = 0, riffSize: UInt32 = 0, dataSize: UInt32 = 0) -> Data {
        var out = Data("RIFF".utf8) + WAVRepair.littleEndian(riffSize) + Data("WAVE".utf8)
        out += Data("fmt ".utf8) + WAVRepair.littleEndian(16) + Data(repeating: 0, count: 16)
        if filler > 0 {
            out += Data("FLLR".utf8) + WAVRepair.littleEndian(UInt32(filler)) + Data(repeating: 0, count: filler)
        }
        out += Data("data".utf8) + WAVRepair.littleEndian(dataSize)
        return out
    }

    @Test func theSizesAreWorkedOutFromTheFileLength() throws {
        let head = Self.header()
        let fix = try #require(WAVRepair.fix(prefix: head, fileLength: head.count + 32_000))
        #expect(fix.dataSize == 32_000)
        #expect(fix.riffSize == UInt32(head.count + 32_000 - 8))
        #expect(fix.dataSizeOffset == head.count - 4)
    }

    @Test func aFillerChunkBeforeTheDataIsSteppedOver() throws {
        let head = Self.header(filler: 4_044)
        let fix = try #require(WAVRepair.fix(prefix: head, fileLength: head.count + 100))
        #expect(fix.dataSize == 100)
        #expect(fix.dataSizeOffset == head.count - 4)
    }

    @Test func whatIsNotAWavIsLeftAlone() {
        #expect(WAVRepair.fix(prefix: Data("not a wav file at all".utf8), fileLength: 21) == nil)
        #expect(WAVRepair.fix(prefix: Data(), fileLength: 0) == nil)
        // A WAV whose data chunk is not in the first bytes read.
        let noData = Data("RIFF".utf8) + WAVRepair.littleEndian(0) + Data("WAVE".utf8)
        #expect(WAVRepair.fix(prefix: noData, fileLength: 100) == nil)
    }

    @Test func aFileThatWasNeverClosedIsMadeReadable() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cut-\(UUID().uuidString).wav")
        let head = Self.header(filler: 20)
        let audio = Data(repeating: 7, count: 5_000)
        try (head + audio).write(to: url)
        #expect(WAVRepair.repair(fileAt: url))
        let fixed = try Data(contentsOf: url)
        #expect(fixed.count == head.count + audio.count)
        #expect(fixed.suffix(audio.count) == audio)
        let again = try #require(WAVRepair.fix(prefix: fixed.prefix(8192), fileLength: fixed.count))
        #expect(Data(fixed[again.dataSizeOffset..<(again.dataSizeOffset + 4)]) == WAVRepair.littleEndian(5_000))
        #expect(Data(fixed[4..<8]) == WAVRepair.littleEndian(UInt32(fixed.count - 8)))
        // A file that is already right is not touched.
        #expect(!WAVRepair.repair(fileAt: url))
    }
}

@Suite("A note exists before its recording does")
@MainActor
struct RecordingNoteTests {
    @Test func beginningWritesTheNoteAndNamesTheFileToRecordInto() throws {
        let root = NoteStoreTests.temporaryRoot()
        let store = NoteStore(root: root)
        let (note, audio) = try #require(store.begin(source: "Recorded here", localeId: "en-GB"))
        #expect(note.processing)
        #expect(audio.lastPathComponent == "audio.wav")
        #expect(audio.deletingLastPathComponent() == store.folderURL(for: note.id))
        // Nothing recorded yet: the note is there, the audio is not.
        #expect(store.audioURL(for: note.id) == nil)
        #expect(NoteStore(root: root).notes.map(\.id) == [note.id])
    }

    @Test func aRecordingCutOffByACrashIsRepairedWhenTheLibraryOpens() throws {
        let root = NoteStoreTests.temporaryRoot()
        let store = NoteStore(root: root)
        let (note, audio) = try #require(store.begin(source: "Recorded here", localeId: "en-GB"))
        // What the recorder leaves if the app dies: audio on disk, header sizes still zero.
        let head = WAVRepairTests.header()
        try (head + Data(repeating: 3, count: 1_000)).write(to: audio)

        let reopened = NoteStore(root: root)
        let found = try #require(reopened.note(note.id))
        #expect(found.processing)
        let kept = try #require(reopened.audioURL(for: note.id))
        let bytes = try Data(contentsOf: kept)
        #expect(Data(bytes[(head.count - 4)..<head.count]) == WAVRepair.littleEndian(1_000))
    }

    @Test func theCompressedCopyTakesTheRecordingsPlace() throws {
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let (note, audio) = try #require(store.begin(source: "Recorded here", localeId: "en-GB"))
        try Data([1]).write(to: audio)
        try Data([2, 2]).write(to: store.folderURL(for: note.id).appending(path: "audio.m4a"))
        store.replaceAudio(note.id, with: "audio.m4a")
        #expect(store.note(note.id)?.audioName == "audio.m4a")
        #expect(store.audioURL(for: note.id)?.lastPathComponent == "audio.m4a")
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }
}

@Suite("The session's states")
@MainActor
struct SessionStateTests {
    @Test func processingRecordingAndIdleReadAsTheyShould() throws {
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let session = DebriefSession(store: store)
        let note = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB"))
        session.showSample(phase: .working("Writing the debrief"), noteId: note.id)
        #expect(session.isProcessing)
        #expect(session.workingText(for: note.id) == "Writing the debrief")
        session.showSample(phase: .recording(since: Date()), noteId: note.id)
        guard case .recording = session.phase else { Issue.record("expected the recording state"); return }
        #expect(session.isBusy)
        session.showSample(phase: .idle)
        #expect(session.phase == .idle)
        #expect(!session.isBusy)
        #expect(session.waiting.isEmpty)
    }
}
