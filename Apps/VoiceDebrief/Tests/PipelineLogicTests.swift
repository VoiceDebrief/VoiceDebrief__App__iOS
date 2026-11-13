import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Timecode")
struct TimecodeTests {
    @Test func minutesAndSeconds() {
        #expect(Timecode.format(ms: 0) == "00:00")
        #expect(Timecode.format(ms: 65_400) == "01:05")
        #expect(Timecode.format(ms: 599_999) == "09:59")
    }

    @Test func anHourUp() {
        #expect(Timecode.format(ms: 3_600_000) == "1:00:00")
        #expect(Timecode.format(ms: 3_725_000) == "1:02:05")
    }

    @Test func negativeReadsAsZero() {
        #expect(Timecode.format(ms: -5) == "00:00")
    }

    @Test func durations() {
        #expect(Timecode.duration(seconds: 1.24) == "1.2 s")
        #expect(Timecode.duration(seconds: 185) == "3 min 05 s")
    }
}

@Suite("Transcript")
struct TranscriptTests {
    static let lines = [
        TranscriptLine(startMs: 0, endMs: 4_000, text: "Hello, this is a test."),
        TranscriptLine(startMs: 4_000, endMs: 61_000, text: "Call Maria on Tuesday."),
    ]

    @Test func timedTextHasOneLinePerPhrase() {
        let transcript = Transcript(localeId: "en-GB", lines: Self.lines)
        #expect(transcript.timedText == "[00:00] Hello, this is a test.\n[00:04] Call Maria on Tuesday.")
        #expect(transcript.durationMs == 61_000)
        #expect(!transcript.isEmpty)
    }

    @Test func anEmptyTranscriptIsEmpty() {
        let transcript = Transcript(localeId: "en-GB", lines: [])
        #expect(transcript.isEmpty)
        #expect(transcript.durationMs == 0)
        #expect(transcript.timedText == "")
    }
}

@Suite("Chunker")
struct ChunkerTests {
    static func lines(_ count: Int, length: Int) -> [TranscriptLine] {
        (0..<count).map { TranscriptLine(startMs: $0 * 1000, endMs: $0 * 1000 + 900, text: String(repeating: "a", count: length)) }
    }

    @Test func aShortNoteIsOneChunk() {
        let chunks = Chunker.chunks(Self.lines(5, length: 50), budget: 1000)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 5)
    }

    @Test func aLongNoteIsSplitAndNothingIsLost() {
        let lines = Self.lines(40, length: 100)
        let chunks = Chunker.chunks(lines, budget: 1000)
        #expect(chunks.count > 1)
        #expect(chunks.flatMap { $0 } == lines)
        for chunk in chunks {
            #expect(Transcript.timedText(chunk).count <= 1000)
        }
    }

    @Test func aLineLongerThanTheBudgetIsKeptWhole() {
        let lines = Self.lines(3, length: 500)
        let chunks = Chunker.chunks(lines, budget: 200)
        #expect(chunks.count == 3)
        #expect(chunks.flatMap { $0 } == lines)
    }

    @Test func noLinesNoChunks() {
        #expect(Chunker.chunks([], budget: 1000).isEmpty)
    }

    @Test func theBudgetGrowsWithTheContextAndHasAFloor() {
        #expect(Chunker.characterBudget(contextSize: 4096) == (4096 - Chunker.reservedTokens) * Chunker.charactersPerToken)
        #expect(Chunker.characterBudget(contextSize: 8192) > Chunker.characterBudget(contextSize: 4096))
        #expect(Chunker.characterBudget(contextSize: 100) == 1500)
    }
}

@Suite("Debrief prompt")
struct DebriefPromptTests {
    @Test func portugueseOfPortugalIsNotBrazilian() {
        #expect(DebriefPrompt.voice(forLocale: "pt-PT").language == "European Portuguese")
        #expect(DebriefPrompt.voice(forLocale: "pt_PT").language == "European Portuguese")
        #expect(DebriefPrompt.voice(forLocale: "pt-BR").language == "Brazilian Portuguese")
    }

    @Test func englishByRegion() {
        #expect(DebriefPrompt.voice(forLocale: "en-GB").language == "British English")
        #expect(DebriefPrompt.voice(forLocale: "en-US").language == "American English")
        #expect(DebriefPrompt.voice(forLocale: "en-AU").language == "British English")
    }

    @Test func thePromptCarriesTheTranscriptTheLanguageAndTheHeadings() {
        let voice = DebriefPrompt.voice(forLocale: "pt-PT")
        let prompt = DebriefPrompt.debrief(transcript: "[00:00] Olá.", voice: voice)
        #expect(prompt.contains("[00:00] Olá."))
        #expect(prompt.contains("European Portuguese"))
        for heading in DebriefPrompt.sections { #expect(prompt.contains(heading)) }
    }

    @Test func thePromptHasNoQuotationMarksToCopy() {
        // The first runs came back with bullets in quotation marks, copied from the prompt's own examples.
        let voice = DebriefPrompt.voice(forLocale: "en-GB")
        let shell = DebriefPrompt.debrief(transcript: "", voice: voice)
        #expect(!shell.contains("\""))
        #expect(!DebriefPrompt.merge(notes: "", voice: voice).contains("\""))
        #expect(!DebriefPrompt.notes(section: 1, of: 2, transcript: "", voice: voice).contains("\""))
    }

    @Test func wordsAreCountedAcrossLines() {
        let lines = [
            TranscriptLine(startMs: 0, endMs: 1, text: "Okay, let's see if it works."),
            TranscriptLine(startMs: 1, endMs: 2, text: "  Two   words "),
        ]
        #expect(DebriefPrompt.wordCount(lines) == 8)
        #expect(DebriefPrompt.wordCount([]) == 0)
        #expect(DebriefPrompt.minimumWords > 8)
    }

    @Test func theSectionPromptSaysWhichPartItIs() {
        let prompt = DebriefPrompt.notes(section: 2, of: 3, transcript: "[05:00] x", voice: DebriefPrompt.voice(forLocale: "en-GB"))
        #expect(prompt.contains("part 2 of 3"))
        #expect(prompt.contains("[05:00] x"))
    }

    @Test func aDebriefIsCheckedForItsThreeHeadingsInOrder() {
        let good = "## Key points\n- a\n\n## Actions\n- none mentioned\n\n## In one sentence\nA."
        #expect(DebriefPrompt.hasAllSections(good))
        #expect(!DebriefPrompt.hasAllSections("## Key points\n- a\n## In one sentence\nA."))
        #expect(!DebriefPrompt.hasAllSections("## Actions\n- a\n## Key points\n- b\n## In one sentence\nA."))
    }
}

@Suite("Debrief markdown")
struct DebriefMarkdownTests {
    @Test func headingsBulletsAndParagraphs() {
        let blocks = DebriefMarkdown.blocks("## Key points\n- **First** point\n* second\n\n## In one sentence\nIt went well.")
        #expect(blocks == [
            .heading("Key points"), .bullet("First point"), .bullet("second"),
            .heading("In one sentence"), .paragraph("It went well."),
        ])
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(DebriefMarkdown.blocks("\n  \n").isEmpty)
    }
}

@Suite("Run and diagnostics")
struct RunTests {
    static func run() -> DebriefRun {
        var run = DebriefRun(source: "note.m4a", localeId: "en-GB")
        run.transcript = Transcript(localeId: "en-GB", lines: [TranscriptLine(startMs: 0, endMs: 1000, text: "A secret plan.")])
        run.debrief = "## Key points\n- A secret plan."
        run.steps = [StepRecord(name: "Transcript", outcome: .done, seconds: 1.5, note: "1 lines")]
        return run
    }

    @Test func theSharedDocumentHasTheDebriefTheTranscriptAndTheCaveat() {
        let text = Self.run().markdown
        #expect(text.contains("## Key points"))
        #expect(text.contains("[00:00] A secret plan."))
        #expect(text.contains("not a stenographer"))
    }

    @Test func theDiagnosticsExportHoldsNoWords() {
        let stripped = Diagnostics.withoutContent(Self.run())
        #expect(stripped.source == "Imported file")
        #expect(stripped.debrief == "(30 characters)")
        #expect(stripped.transcript?.lines.first?.text == "(14 characters)")
        #expect(stripped.steps == Self.run().steps)
        let report = Diagnostics(appVersion: "0.1.1 (1)", system: "s", machine: "m", preferredLanguages: [],
                                 speechAvailable: false, speechSupportedLocales: [], speechInstalledLocales: [],
                                 modelStatus: "x", modelContextSize: nil, modelLanguages: [], lastRun: stripped)
        #expect(!report.json.contains("secret"))
        #expect(report.json.contains("\"machine\" : \"m\""))
    }
}
