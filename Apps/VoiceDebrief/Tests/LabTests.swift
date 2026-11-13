import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Lab: the model door's policy and record")
struct LabDoorTests {
    @Test func aPolicyOffersOnlyWhatItNames() {
        let policy = ModelDoorPolicy(tools: [.clock, .readNote])
        #expect(policy.offered(from: LabToolId.allCases) == [.clock, .readNote])
        #expect(policy.withheld(from: LabToolId.allCases) == [.listNotes, .chooseScreen])
        #expect(policy.allows("currentDateTime"))
        #expect(!policy.allows("listNotes"))
        #expect(ModelDoorPolicy.noTools.offered(from: LabToolId.allCases).isEmpty)
    }

    @Test func aPolicyIgnoresNamesThatAreNotTools() {
        let policy = ModelDoorPolicy(allowedTools: ["deleteEverything", "listNotes"])
        #expect(policy.offered(from: LabToolId.allCases) == [.listNotes])
    }

    @Test func theRecorderKeepsCallsInOrderWithWhatTheyReturned() {
        let recorder = ModelDoorRecorder()
        let first = recorder.measure(tool: "listNotes", arguments: ["limit": "3"]) { LabToolResult(text: "There are no notes.", ok: true) }
        _ = recorder.measure(tool: "readNote", arguments: ["id": "x"]) { LabToolResult(text: "There is no note with the id x.", ok: false) }
        #expect(first == "There are no notes.")
        let calls = recorder.toolCalls
        #expect(calls.map(\.order) == [1, 2])
        #expect(calls.map(\.name) == ["listNotes", "readNote"])
        #expect(calls[0].arguments == ["limit": "3"])
        #expect(calls[1].result == "There is no note with the id x.")
        #expect(calls.map(\.ok) == [true, false])
        #expect(calls.allSatisfy { $0.durationMs >= 0 })
    }

    @Test func errorsAreSortedIntoPlainWords() {
        #expect(ModelDoorError.classify(raw: "GenerationError.guardrailViolation(Context())", description: "x").kind == "guardrail")
        #expect(ModelDoorError.classify(raw: "GenerationError.exceededContextWindowSize(Context())", description: "x").kind == "contextExceeded")
        #expect(ModelDoorError.classify(raw: "Error.contextSizeExceeded(Context())", description: "x").kind == "contextExceeded")
        #expect(ModelDoorError.classify(raw: "GenerationError.refusal(Refusal(), Context())", description: "x").kind == "refusal")
        let other = ModelDoorError.classify(raw: "SomethingElse()", description: "It broke.")
        #expect(other.kind == "other")
        #expect(other.words == "It broke.")
        #expect(other.raw == "SomethingElse()")
    }
}

@Suite("Lab: runs")
struct LabRunTests {
    static func run(preset: LabPreset?, offered: [LabToolId] = LabToolId.allCases, calls: [(String, [String: String], Bool)] = [],
                    error: ModelDoorError? = nil) -> LabRun {
        var record = ModelDoorRecord(
            startedAt: Date(timeIntervalSince1970: 1_794_000_000),
            instructions: LabDefaults.instructions,
            prompt: preset?.prompt ?? "A prompt",
            policy: ModelDoorPolicy(tools: Set(offered)),
            toolsOffered: offered.map { ModelDoorToolDefinition(name: $0.rawValue, description: $0.summary) },
            toolsWithheld: LabToolId.allCases.filter { !offered.contains($0) }.map(\.rawValue))
        record.toolCalls = calls.enumerated().map { index, call in
            ModelDoorToolCall(order: index + 1, name: call.0, arguments: call.1, result: "result", ok: call.2, durationMs: 0.4)
        }
        record.error = error
        record.totalMs = 1234
        let device = LabDevice(appVersion: "0.0.0 (1)", system: "Version 26.0", machine: "test", modelStatus: "Available", modelContextSize: 4096)
        return LabRun(id: "20261113-170000-abcdef", presetId: preset?.id, expectedTools: preset?.expects.map(\.rawValue),
                      device: device, record: record)
    }

    @Test func aRunSurvivesItsJSON() throws {
        let run = Self.run(preset: LabPreset.find("date"), calls: [("currentDateTime", [:], true)])
        let json = run.json
        #expect(json.contains("\"experiment\" : \"L01\""))
        #expect(json.contains("\"toolCalls\""))
        #expect(json.contains("\"instructions\""))
        let back = try #require(LabRun.decode(json))
        #expect(back == run)
        #expect(LabRun.json(of: [run, run]).hasPrefix("["))
    }

    @Test func theScreenChoiceIsReadFromTheRecordAndOnlyWhenItIsOnTheList() {
        let chosen = Self.run(preset: nil, calls: [("chooseNextScreen", ["screen": "library"], true)])
        #expect(chosen.screenChoice == "library")
        let unknown = Self.run(preset: nil, calls: [("chooseNextScreen", ["screen": "moon"], false)])
        #expect(unknown.screenChoice == nil)
        #expect(Self.run(preset: nil).screenChoice == nil)
    }

    @Test func theVerdictJudgesOnlyTheChoiceOfTool() throws {
        let date = LabPreset.find("date")
        #expect(Self.run(preset: date, calls: [("currentDateTime", [:], true)]).verdict == .right)
        #expect(Self.run(preset: date).verdict == .missed(["currentDateTime"]))
        // Extra calls beside the expected one do not make it wrong.
        #expect(Self.run(preset: date, calls: [("listNotes", ["limit": "5"], true), ("currentDateTime", [:], true)]).verdict == .right)

        let recent = LabPreset.find("recent")
        #expect(Self.run(preset: recent, calls: [("listNotes", ["limit": "1"], true)]).verdict == .missed(["readNote"]))

        let none = LabPreset.find("no-tool")
        #expect(Self.run(preset: none).verdict == .right)
        #expect(Self.run(preset: none, calls: [("currentDateTime", [:], true)]).verdict == .unneeded(["currentDateTime"]))

        // The tool it needs is switched off: calling nothing is right.
        let off = try #require(LabPreset.find("tool-off"))
        #expect(!off.tools.contains(.clock))
        #expect(Self.run(preset: off, offered: Array(off.tools)).verdict == .right)
        #expect(Self.run(preset: off, offered: Array(off.tools), calls: [("listNotes", ["limit": "1"], true)]).verdict == .unneeded(["listNotes"]))

        #expect(Self.run(preset: date, error: ModelDoorError(kind: "guardrail", words: "w", raw: "r")).verdict == .failed)
        #expect(Self.run(preset: nil).verdict == nil)
    }

    @Test func theTallyCountsRightChoicesForEachPresetRun() {
        let date = LabPreset.find("date")
        let runs = [
            Self.run(preset: date, calls: [("currentDateTime", [:], true)]),
            Self.run(preset: date),
            Self.run(preset: LabPreset.find("no-tool")),
            Self.run(preset: nil),
        ]
        let tally = LabTally.of(runs)
        #expect(tally.map(\.presetId) == ["date", "no-tool"])
        #expect(tally.map(\.runs) == [2, 1])
        #expect(tally.map(\.right) == [1, 1])
    }

    @Test func presetsAreDistinctAndNameRealTools() {
        #expect(Set(LabPreset.all.map(\.id)).count == LabPreset.all.count)
        #expect(LabPreset.all.contains { $0.expects.isEmpty })
        #expect(LabPreset.all.contains { preset in preset.expects.contains { !preset.tools.contains($0) } })
        // The words given to a small model hold no quotation marks for it to copy.
        for text in LabPreset.all.map(\.prompt) + LabToolId.allCases.map(\.summary) + [LabDefaults.instructions] {
            #expect(!text.contains("\""))
        }
    }
}

@Suite("Lab: the tools' own logic")
@MainActor
struct LabToolboxTests {
    static let london = TimeZone(identifier: "Europe/London")!

    @Test func theClockSaysTheDateInWords() {
        // 13 November 2026, 17:05 UTC.
        let now = Date(timeIntervalSince1970: 1_794_589_500)
        let toolbox = LabToolbox(notes: [], fixedNow: now, timeZone: Self.london)
        let result = toolbox.currentDateTime()
        #expect(result.ok)
        #expect(result.text == "Friday 13 November 2026, 17:05, time zone Europe/London")
    }

    @Test func theToolsReadALibraryInATemporaryFolder() throws {
        let store = NoteStore(root: NoteStoreTests.temporaryRoot())
        let older = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB",
                                              now: Date(timeIntervalSince1970: 1_794_500_000)))
        let newer = try #require(store.create(audioAt: try NoteStoreTests.audioFile(), source: "Recorded here", localeId: "en-GB",
                                              now: Date(timeIntervalSince1970: 1_794_580_000)))
        var run = older.run
        run.transcript = Transcript(localeId: "en-GB", lines: [
            TranscriptLine(startMs: 0, endMs: 2000, text: "The vault needs a second remote."),
            TranscriptLine(startMs: 2000, endMs: 4000, text: "Ask about the entitlement."),
        ])
        store.update(older.id, run: run, processing: false)
        let before = store.notes

        let toolbox = LabToolbox(store: store)
        #expect(toolbox.notes.map(\.id) == [newer.id, older.id])

        let list = toolbox.listNotes(limit: 20)
        #expect(list.ok)
        let lines = list.text.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("id \(newer.id) | "))
        #expect(lines[1].contains("The vault needs a second remote."))

        let one = toolbox.listNotes(limit: 1).text.components(separatedBy: "\n")
        #expect(one.count == 2)
        #expect(one[1] == "1 older notes are not listed.")

        let read = toolbox.readNote(id: " \(older.id) ")
        #expect(read.ok)
        #expect(read.text == "[00:00] The vault needs a second remote.\n[00:02] Ask about the entitlement.")

        #expect(!toolbox.readNote(id: newer.id).ok)
        let missing = toolbox.readNote(id: "nothing")
        #expect(!missing.ok)
        #expect(missing.text == "There is no note with the id nothing.")

        // Reading changed nothing.
        #expect(store.notes == before)
    }

    @Test func anEmptyLibrarySaysSo() {
        #expect(LabToolbox(notes: []).listNotes(limit: 5).text == "There are no notes.")
    }

    @Test func aLongTranscriptIsCutAndSaysSo() {
        let long = String(repeating: "word ", count: 600)
        let toolbox = LabToolbox(notes: [LabNote(id: "a", createdAt: Date(), title: "Long", transcript: long)])
        let result = toolbox.readNote(id: "a")
        #expect(result.ok)
        #expect(result.text.hasSuffix("The transcript is longer than this and was cut here."))
        #expect(result.text.count < LabToolbox.transcriptLimit + 80)
    }

    @Test func aScreenChoiceMustBeOnTheList() {
        let toolbox = LabToolbox(notes: [])
        #expect(toolbox.chooseScreen(" Library ").ok)
        #expect(toolbox.chooseScreen("library").text == "The choice of the library screen is recorded.")
        let unknown = toolbox.chooseScreen("moon")
        #expect(!unknown.ok)
        #expect(unknown.text.contains("record, library, note, vaults, settings"))
    }
}
