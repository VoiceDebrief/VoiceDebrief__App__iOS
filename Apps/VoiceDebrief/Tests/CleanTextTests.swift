import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Clean text")
struct CleanTextTests {
    static func line(_ start: Int, _ words: Int, _ word: String = "word") -> TranscriptLine {
        TranscriptLine(startMs: start, endMs: start + 1000, text: Array(repeating: word, count: words).joined(separator: " "))
    }

    @Test func linesAreGatheredIntoPassagesWithoutBeingSplit() {
        let lines = [Self.line(0, 60), Self.line(1000, 40), Self.line(2000, 30), Self.line(3000, 200), Self.line(4000, 5)]
        let passages = Passages.split(lines, targetWords: 110)
        #expect(passages.map(\.startMs) == [0, 2000, 3000, 4000])
        #expect(passages.map { WordDiff.words($0.heard).count } == [100, 30, 200, 5])
        #expect(passages[0].endMs == 2000)
        #expect(passages.allSatisfy { $0.clean == nil && $0.questions.isEmpty })
    }

    @Test func nothingSaidMakesNoPassages() {
        #expect(Passages.split([]).isEmpty)
        #expect(Passages.split([TranscriptLine(startMs: 0, endMs: 10, text: "  ")]).isEmpty)
    }

    @Test func thePromptCarriesThePassageAndTheSpeakersWords() {
        let terms = [GlossaryTerm(word: "vault", heardAs: ["vote", "volt"]), GlossaryTerm(word: "sgit", heardAs: [])]
        let prompt = CleanPrompt.make(heard: "save it to the vote", glossary: terms, localeId: "en-GB")
        #expect(prompt.contains("- vault (sometimes heard as: vote, volt)"))
        #expect(prompt.contains("- sgit\n"))
        #expect(prompt.hasSuffix("Passage:\nsave it to the vote"))
        #expect(!prompt.contains("\""))
        let bare = CleanPrompt.make(heard: "hello", glossary: [], localeId: "en-GB")
        #expect(!bare.contains("words I use"))
    }

    @Test func variantsAreTidiedAndNeverTheWordItself() {
        #expect(Glossary.variants(from: " vote, Volt ,vote;; vault ", word: "Vault") == ["vote", "Volt"])
    }

    @Test func addingATermTwiceMergesWhatItWasHeardAs() {
        var terms = Glossary.adding("vault", heardAs: ["vote"], to: [])
        terms = Glossary.adding("Vault", heardAs: ["volt", "vote"], to: terms)
        terms = Glossary.adding("  ", heardAs: ["x"], to: terms)
        #expect(terms == [GlossaryTerm(word: "vault", heardAs: ["vote", "volt"])])
    }

    @Test func theDiffShowsWhatWasTakenOutAndPutIn() {
        let segments = WordDiff.segments(heard: "so um save it to the vote, right", clean: "Save it to the vault.")
        #expect(segments == [
            .init(kind: .removed, text: "so um"),
            .init(kind: .same, text: "Save it to the"),
            .init(kind: .removed, text: "vote, right"),
            .init(kind: .added, text: "vault."),
        ])
        #expect(WordDiff.segments(heard: "", clean: "new") == [.init(kind: .added, text: "new")])
        #expect(WordDiff.segments(heard: "old", clean: "") == [.init(kind: .removed, text: "old")])
    }

    @Test func aRewriteHalfTheLengthIsFlagged() {
        var passage = Passages.split([Self.line(0, 40)])[0]
        passage.clean = Array(repeating: "word", count: 19).joined(separator: " ")
        #expect(passage.looksCut)
        passage.clean = Array(repeating: "word", count: 30).joined(separator: " ")
        #expect(!passage.looksCut)
    }

    @Test func aNoteWrittenBeforeCleanTextExistedStillOpens() throws {
        let old = #"{"id":"n1","createdAt":"2026-11-13T10:00:00Z","processing":false,"audioName":"audio.m4a","run":{"source":"Recorded here","localeId":"en-GB","sections":0,"debriefHasAllSections":false,"steps":[]}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try decoder.decode(Note.self, from: Data(old.utf8))
        #expect(note.clean == nil)
    }

    @Test @MainActor func aNewTranscriptDropsTheCleanTextMadeFromTheOldOne() throws {
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let note = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB"))
        var run = note.run
        run.transcript = Transcript(localeId: "en-GB", lines: [Self.line(0, 30)])
        store.update(note.id, run: run, processing: false)
        store.setClean(note.id, CleanText(passages: Passages.split(run.transcript!.lines), madeAt: Date(),
                                          glossaryWords: [], contextSize: nil, finished: true))
        store.update(note.id, run: run, processing: false)
        #expect(store.note(note.id)?.clean != nil)
        #expect(NoteStore(root: store.root).note(note.id)?.clean?.passages.count == 1)
        run.transcript = Transcript(localeId: "en-GB", lines: [Self.line(0, 31)])
        store.update(note.id, run: run, processing: false)
        #expect(store.note(note.id)?.clean == nil)
    }

    @Test func theCleanTextTravelsOverTheLane() throws {
        let clean = CleanText(passages: Passages.split([Self.line(0, 30)]), madeAt: Date(timeIntervalSince1970: 0),
                              glossaryWords: ["vault"], contextSize: 4096, finished: true)
        let run = DebriefRun(source: "Recorded here", localeId: "en-GB")
        let without = try DeveloperLane.messages(audio: Data([1, 2]), audioName: "a.m4a", run: run, noteId: "n", app: "t", at: Date())
        let with = try DeveloperLane.messages(audio: Data([1, 2]), audioName: "a.m4a", run: run, clean: clean, noteId: "n", app: "t", at: Date())
        #expect(with.count == without.count + 1)
        let last = try #require(with.last)
        let header = try JSONDecoder().decode(DeveloperLane.Header.self, from: last.prefix(while: { $0 != 0x0A }))
        #expect(header.kind == DeveloperLane.Header.cleanKind)
        #expect(header.name == "clean.json")
    }
}
