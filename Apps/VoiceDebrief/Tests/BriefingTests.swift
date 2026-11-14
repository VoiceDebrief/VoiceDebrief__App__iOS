import Foundation
import Testing
@testable import VoiceDebrief

@Suite("The briefing on opening")
struct BriefingTests {
    static func note(_ id: String, at seconds: TimeInterval, audio: Double = 60, processing: Bool = false) -> Note {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        run.audioSeconds = audio
        return Note(id: id, createdAt: Date(timeIntervalSince1970: seconds), run: run, audioName: "audio.m4a", processing: processing)
    }

    @Test func theFirstOpeningSaysNothing() {
        let b = Briefing.make(notes: [Self.note("a", at: 10)], since: nil, lastVersion: nil, version: "v0.1.33")
        #expect(b.isEmpty)
    }

    @Test func newNotesInterruptedOnesSendsAndSavesAreCounted() {
        var sent = Self.note("b", at: 200)
        sent.sends = [NoteSend(to: "Maria", at: Date(timeIntervalSince1970: 300))]
        sent.saves = [NoteSave(vaultId: "v", vaultName: "Notes", at: Date(timeIntervalSince1970: 301))]
        let notes = [Self.note("a", at: 50), sent, Self.note("c", at: 250, audio: 90, processing: true)]
        let b = Briefing.make(notes: notes, since: Date(timeIntervalSince1970: 100), lastVersion: "v0.1.33", version: "v0.1.33")
        #expect(b.upgradedTo == nil)
        #expect(b.lines == [
            "2 new notes since you last looked, 3 min in all.",
            "1 note was interrupted: its recording is kept; open it to run it again.",
            "Sent 1 note to Maria.",
            "Saved 1 note to your vault.",
        ])
    }

    @Test func anUpgradeIsNoticed() {
        let b = Briefing.make(notes: [], since: Date(timeIntervalSince1970: 0), lastVersion: "v0.1.32", version: "v0.1.33")
        #expect(b.upgradedTo == "v0.1.33")
        #expect(!b.isEmpty)
    }
}
