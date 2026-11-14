import Foundation
import Testing
@testable import VoiceDebrief

@Suite("The one mark on a note's row")
struct NoteMarkTests {
    static func note(words: Bool = true, processing: Bool = false) -> Note {
        var run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        if words { run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 900, text: "Hello")]) }
        return Note(id: "n", createdAt: Date(timeIntervalSince1970: 0), run: run, audioName: "audio.m4a", processing: processing)
    }

    @Test func aFinishedNoteOnlyOnThisDeviceHasNoMark() {
        #expect(NoteMark.of(Self.note(), working: nil) == .none)
    }

    @Test func workNowComesFirst() {
        var n = Self.note(processing: true)
        n.sendProblem = "offline"
        #expect(NoteMark.of(n, working: "Transcribing") == .working("Transcribing"))
    }

    @Test func aFailedSendNamesWhoItWasFor() {
        var n = Self.note()
        n.pendingSend = Recipient(name: "Sam", link: "x")
        n.sendProblem = "offline"
        #expect(NoteMark.of(n, working: nil) == .failed("Not sent to Sam"))
    }

    @Test func aFailedSaveOutranksBeingInAVault() {
        var n = Self.note()
        n.saves = [NoteSave(vaultId: "v", vaultName: "Notes", at: Date(timeIntervalSince1970: 1))]
        n.saveProblem = "no network"
        #expect(NoteMark.of(n, working: nil) == .failed("Not saved to the vault"))
    }

    @Test func unfinishedNotesSaySo() {
        #expect(NoteMark.of(Self.note(processing: true), working: nil) == .degraded("Interrupted"))
        #expect(NoteMark.of(Self.note(words: false), working: nil) == .degraded("No words found"))
    }

    @Test func aSavedNoteNamesTheLastVault() {
        var n = Self.note()
        n.saves = [NoteSave(vaultId: "a", vaultName: "Old", at: Date(timeIntervalSince1970: 1)),
                   NoteSave(vaultId: "b", vaultName: "Work", at: Date(timeIntervalSince1970: 2))]
        #expect(NoteMark.of(n, working: nil) == .inVault("Work"))
    }
}
