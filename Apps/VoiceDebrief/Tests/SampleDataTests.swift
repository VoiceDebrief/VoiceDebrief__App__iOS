import Foundation
import Testing
@testable import VoiceDebrief

/// The launch arguments and the invented data behind the screenshots (issue 016).
@Suite("Sample data")
@MainActor
struct SampleDataTests {
    @Test func withoutTheArgumentThereIsNoSampleData() {
        #expect(LaunchOptions.sampleSet(in: ["VoiceDebrief"]) == nil)
        #expect(LaunchOptions.sampleSet(in: ["VoiceDebrief", "-VDSampleData"]) == nil)
        #expect(LaunchOptions.sampleSet(in: ["VoiceDebrief", "-VDSampleData", "real"]) == nil)
        #expect(LaunchOptions.sampleSet(in: ["VoiceDebrief", "-VDSampleData", "full"]) == .full)
        #expect(LaunchOptions.sampleSet(in: ["VoiceDebrief", "-VDSampleData", "empty"]) == .empty)
        // The unit tests themselves are a normal launch: no sample world, and the one-file stores stay where they are.
        #expect(SampleWorld.launched == nil)
        #expect(LaunchOptions.sampleFile("credit-ledger.json") == nil)
    }

    @Test func aScreenIsOpenedOnlyOverSampleData() {
        #expect(LaunchOptions.screen(in: ["VoiceDebrief", "-VDScreen", "settings"]) == nil)
        #expect(LaunchOptions.screen(in: ["VoiceDebrief", "-VDSampleData", "full", "-VDScreen", "note.finished"]) == .noteFinished)
        #expect(LaunchOptions.screen(in: ["VoiceDebrief", "-VDSampleData", "full", "-VDScreen", "nowhere"]) == .record)
        #expect(LaunchOptions.screen(in: ["VoiceDebrief", "-VDSampleData", "empty"]) == .record)
    }

    @Test func everyScreenHasItsOwnIdAndATab() {
        let ids = LaunchScreen.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
        for screen in LaunchScreen.allCases where screen.isPushed {
            #expect(screen.tab != .record)
        }
    }

    @Test func everySampleNoteSaysItIsInvented() {
        for sample in [SampleData.finished, SampleData.transcriptOnly, SampleData.interrupted, SampleData.working, SampleData.recording] {
            #expect(sample.run.source == SampleData.source)
            if let first = sample.run.transcript?.lines.first?.text {
                #expect(first.lowercased().contains("invented sample"))
            }
        }
        let debrief = SampleData.finished.run.debrief ?? ""
        #expect(debrief.contains("Invented sample"))
        #expect(DebriefPrompt.hasAllSections(debrief))
        #expect(SampleData.levels.count == DebriefSession.levelCount)
        #expect(SampleData.levels.allSatisfy { (0...1).contains($0) })
    }

    @Test func theFullSetHasOneNoteInEachState() throws {
        let world = SampleWorld(set: .full, screen: .library)
        #expect(world.store.root.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(world.store.root != NoteStore.defaultRoot)
        let states = world.store.notes.map(\.stateLine)
        // Newest first: being written, finished, transcript only, interrupted.
        #expect(states == ["Not finished", "On this device", "Transcript only", "Not finished"])
        let working = try #require(world.noteIds[.working])
        #expect(world.session.workingText(for: working) == "Writing the debrief")
        let interrupted = try #require(world.noteIds[.interrupted])
        #expect(world.session.workingText(for: interrupted) == nil)
        #expect(world.store.audioURL(for: interrupted) != nil)
        let finishedId = try #require(world.noteIds[.finished])
        let finished = try #require(world.store.note(finishedId))
        #expect(finished.title.hasPrefix("Invented sample"))
        #expect(world.book.remotes.map(\.name) == [SampleData.serverName])
        #expect(world.book.localRoot.path.hasPrefix(world.root.path))
        #expect(world.book.localRoot != VaultBook.localFolder)
    }

    @Test func theRecordingScreenIsARecordingWithoutAMicrophone() {
        let world = SampleWorld(set: .full, screen: .recordRecording)
        guard case .recording = world.session.phase else {
            Issue.record("not recording")
            return
        }
        #expect(!world.session.liveSettled.isEmpty)
        #expect(world.session.levels.count == DebriefSession.levelCount)
    }

    @Test func theEmptySetIsEmpty() {
        let world = SampleWorld(set: .empty, screen: .library)
        #expect(world.store.notes.isEmpty)
        #expect(world.book.vaults.isEmpty)
        #expect(world.book.remotes.isEmpty)
        #expect(world.session.phase == .idle)
        #expect(world.vault == nil)
    }

    @Test func theSampleVaultIsARealVaultOnThisDevice() async throws {
        let world = SampleWorld(set: .full, screen: .vaultDetail)
        #expect(world.vault == nil)
        await world.prepareVault()
        #expect(world.vaultProblem == nil)
        let vault = try #require(world.vault)
        #expect(vault.name == SampleData.vaultName)
        #expect(vault.onDevice)
        #expect(FileManager.default.fileExists(atPath: world.book.folder(of: vault.id).appending(path: "bare/refs").path))
        // Read back through the book: the debrief that was saved is there, with no network.
        let contents = try await world.book.contents(of: vault)
        #expect(contents.files.contains { $0.path.hasSuffix("debrief.md") })
        #expect(contents.history.count == 2)
    }
}
