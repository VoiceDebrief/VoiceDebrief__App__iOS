import Foundation
import Testing
@testable import VoiceDebrief

@Suite("The share inbox: from the share extension to a note")
@MainActor
struct ShareInboxTests {
    static func inbox() -> ShareInbox {
        ShareInbox(root: FileManager.default.temporaryDirectory.appending(path: "inbox-test-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    static func sourceFile(named name: String = "PTT-20261117-WA0003.opus") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "shared-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try FileManager.default.copyItem(at: try OggFixtureFiles.url("oggfixture-tone-440-short.opus"), to: url)
        return url
    }

    @Test func aKeptFileIsWaitingWithItsRecord() throws {
        let inbox = Self.inbox()
        let source = try Self.sourceFile()
        let parcel = try inbox.keep(fileAt: source, originalName: "PTT-20261117-WA0003.opus",
                                    typeIdentifier: "org.xiph.opus", seconds: 0.6)
        // The source is not touched; the copy is the same bytes.
        #expect(FileManager.default.fileExists(atPath: source.path))
        let waiting = inbox.waiting()
        #expect(waiting.map(\.parcel) == [parcel])
        let file = try #require(waiting.first?.file)
        #expect(try Data(contentsOf: file) == Data(contentsOf: source))
        #expect(parcel.fileName == "PTT-20261117-WA0003.opus")
        #expect(parcel.bytes == 1_449)
        #expect(parcel.format == ShareParcel.format)
        // The record is plain JSON beside the file.
        let record = try String(contentsOf: file.deletingLastPathComponent().appending(path: "parcel.json"), encoding: .utf8)
        #expect(record.contains("\"typeIdentifier\" : \"org.xiph.opus\""))
    }

    @Test func halfWrittenAndUnreadableParcelsAreLeftAlone() throws {
        let inbox = Self.inbox()
        try FileManager.default.createDirectory(at: inbox.root.appending(path: "20261117-090000-aaaa.partial"), withIntermediateDirectories: true)
        let broken = inbox.root.appending(path: "20261117-090000-bbbb", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appending(path: "parcel.json"))
        #expect(inbox.waiting().isEmpty)
        // Nothing is deleted by guesswork.
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }

    @Test func parcelsComeOutOldestFirst() throws {
        let inbox = Self.inbox()
        let later = try inbox.keep(fileAt: try Self.sourceFile(), originalName: "b.opus", typeIdentifier: "org.xiph.opus",
                                   seconds: nil, now: Date(timeIntervalSince1970: 1_794_900_100))
        let earlier = try inbox.keep(fileAt: try Self.sourceFile(), originalName: "a.opus", typeIdentifier: "org.xiph.opus",
                                     seconds: nil, now: Date(timeIntervalSince1970: 1_794_900_000))
        #expect(inbox.waiting().map(\.parcel.id) == [earlier.id, later.id])
        inbox.remove(earlier.id)
        #expect(inbox.waiting().map(\.parcel.id) == [later.id])
    }

    @Test func namesAreMadeSafe() {
        #expect(ShareInbox.safeName("PTT-20261117-WA0003.opus") == "PTT-20261117-WA0003.opus")
        #expect(ShareInbox.safeName("../../etc/passwd") == "_.._etc_passwd")
        #expect(ShareInbox.safeName("Áudio do João.ogg") == "Áudio do João.ogg")
        #expect(ShareInbox.safeName("...") == "voice-note")
        #expect(ShareInbox.safeName(String(repeating: "a", count: 300) + ".opus").count == 120)
    }

    @Test func theAppTakesAParcelIntoTheLibraryAndOnlyThenRemovesIt() throws {
        let inbox = Self.inbox()
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let session = DebriefSession(store: store)
        try inbox.keep(fileAt: try Self.sourceFile(), originalName: "PTT-20261117-WA0003.opus",
                       typeIdentifier: "org.xiph.opus", seconds: 0.6)
        let made = session.takeShared(from: inbox, localeId: "en-GB")
        #expect(made.count == 1)
        let note = try #require(store.note(made[0]))
        #expect(note.run.source == "Shared: PTT-20261117-WA0003.opus")
        #expect(note.run.localeId == "en-GB")
        #expect(note.audioName == "audio.opus")
        #expect(store.audioURL(for: note.id) != nil)
        #expect(inbox.waiting().isEmpty)
        #expect(session.notice?.contains("shared from another app") == true)
        // Taking again makes nothing more.
        #expect(session.takeShared(from: inbox, localeId: "en-GB").isEmpty)
    }

    @Test func aParcelWhoseNoteCannotBeWrittenStaysWaiting() throws {
        let inbox = Self.inbox()
        // A library whose root is a file, not a folder: no note can be written there.
        let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        let store = NoteStore(root: blocked)
        let session = DebriefSession(store: store)
        try inbox.keep(fileAt: try Self.sourceFile(), originalName: "kept.opus", typeIdentifier: "org.xiph.opus", seconds: nil)
        #expect(session.takeShared(from: inbox, localeId: "en-GB").isEmpty)
        #expect(inbox.waiting().count == 1)
    }
}
