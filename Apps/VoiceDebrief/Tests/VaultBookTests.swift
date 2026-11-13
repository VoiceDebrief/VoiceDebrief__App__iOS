import Foundation
import Testing
import SGitVault
@testable import VoiceDebrief

@Suite("Vault book")
@MainActor
struct VaultBookTests {
    static func run() -> DebriefRun {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 900, text: "Hello there.")])
        run.debrief = "## Key points\n- Hello.\n"
        return run
    }

    @Test func aDebriefBecomesOneDatedFolder() throws {
        let date = Date(timeIntervalSince1970: 1_794_528_000)       // 13 November 2026, 00:00 UTC
        let files = VaultBook.files(for: Self.run(), audio: Data([1, 2, 3]), audioName: "voice-note-1.m4a", id: "abc12345", date: date)
        #expect(Set(files.keys) == [
            "debriefs/2026/11/13/abc12345/debrief.md",
            "debriefs/2026/11/13/abc12345/transcript.md",
            "debriefs/2026/11/13/abc12345/run.json",
            "debriefs/2026/11/13/abc12345/audio.m4a",
        ])
        #expect(files["debriefs/2026/11/13/abc12345/transcript.md"] == Data("[00:00] Hello there.\n".utf8))
        #expect(files["debriefs/2026/11/13/abc12345/audio.m4a"] == Data([1, 2, 3]))
        let saved = try JSONDecoder().decode(DebriefRun.self, from: try #require(files["debriefs/2026/11/13/abc12345/run.json"]))
        #expect(saved == Self.run())
    }

    @Test func withoutAudioOrDebriefOnlyWhatExistsIsWritten() {
        var run = Self.run()
        run.debrief = nil
        let files = VaultBook.files(for: run, audio: nil, audioName: nil, id: "x", date: Date(timeIntervalSince1970: 0))
        #expect(Set(files.keys) == ["debriefs/1970/01/01/x/transcript.md", "debriefs/1970/01/01/x/run.json"])
    }

    @Test func theTokenIsKeptAndRemoved() {
        let store = MemoryStore()
        let book = VaultBook(store: store)
        #expect(!book.hasToken)
        book.setToken("  abc  ")
        #expect(book.hasToken)
        #expect(store.get("access-token") == Data("abc".utf8))
        #expect(VaultBook(store: store).hasToken)
        book.setToken("")
        #expect(!book.hasToken)
        #expect(store.get("access-token") == nil)
    }

    @Test func theSigningKeyIsMadeOnceAndKept() throws {
        let store = MemoryStore()
        let first = try VaultBook(store: store).commitSigner()
        let second = try VaultBook(store: store).commitSigner()
        #expect(first.keyId == second.keyId)
        #expect(first.publicKeyPEM == second.publicKeyPEM)
        #expect(first.keyId.hasPrefix("key-rnd-imm-"))
        let other = try VaultBook(store: MemoryStore()).commitSigner()
        #expect(other.keyId != first.keyId)
    }

    @Test func creatingWithoutATokenSaysSoAndCreatesNothing() async {
        let book = VaultBook(store: MemoryStore())
        await book.create(name: "Test")
        #expect(book.vaults.isEmpty)
        #expect(book.problem?.contains("access token") == true)
        book.clearProblem()
        #expect(book.problem == nil)
    }

    @Test func aVaultKeyWritesAndAReadKeyDoesNot() {
        let vaultKey = SavedVault(id: "abcd1234", name: "a", keyText: VaultCreate.newKeyText(), addedAt: Date(), createdHere: true)
        #expect(vaultKey.canWrite)
        let readKey = SavedVault(id: "abcd1234", name: "b", keyText: "sgit_private_read_" + String(repeating: "0", count: 64) + ":abcd1234",
                                 addedAt: Date(), createdHere: false)
        #expect(!readKey.canWrite)
    }
}
