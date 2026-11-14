import Foundation
import Testing
@testable import SGit

@Suite("What the model's tools can see of a vault")
struct AskTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var toolbox: VaultAskToolbox {
        VaultAskToolbox(facts: VaultFacts(
            files: [.init(path: "stage/Keynote.mov", size: 380_000), .init(path: "stage/IMG_0412.jpg", size: 38_000),
                    .init(path: "team/dinner/IMG_0611.jpg", size: 30_000), .init(path: "README.md", size: 55)],
            commits: [.init(at: now.addingTimeInterval(-600), message: "Add README.md", byThisDevice: true),
                      .init(at: now.addingTimeInterval(-3 * 86_400), message: "Add 3 files", byThisDevice: false)],
            onDevice: false, now: now))
    }

    @Test func theSummaryCountsAndNamesTheTopFolders() {
        let text = toolbox.summary().text
        #expect(text.hasPrefix("4 files, "))
        #expect(text.contains("Folders at the top: stage, team."))
        #expect(text.contains("on a server"))
        #expect(text.contains("Last change: 10 minutes ago."))
    }

    @Test func aFolderListsWhatIsDirectlyInsideIt() {
        let top = toolbox.listFolder("").text
        #expect(top.contains("folder: stage"))
        #expect(top.contains("folder: team"))
        #expect(top.contains("file: README.md"))
        #expect(!top.contains("Keynote"))
        #expect(toolbox.listFolder("/team/").text == "folder: dinner")
        #expect(toolbox.listFolder("nowhere").ok == false)
    }

    @Test func changesSayWhenAndWhichDevice() {
        let lines = toolbox.recentChanges(limit: 5).text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "10 minutes ago, this device: Add README.md")
        #expect(lines[1] == "3 days ago, another device: Add 3 files")
        #expect(toolbox.recentChanges(limit: 1).text.split(separator: "\n").count == 1)
    }

    @Test func filesAreFoundByPartOfTheirName() {
        #expect(toolbox.findFiles(".MOV").text.hasPrefix("stage/Keynote.mov"))
        #expect(toolbox.findFiles("zebra").text == "No file has zebra in its name.")
        #expect(toolbox.findFiles("  ").ok == false)
    }

    @Test func theRecorderKeepsEveryCallInOrder() {
        let recorder = AskRecorder()
        _ = recorder.record("vault_summary", "") { AskToolResult(text: "a", ok: true) }
        _ = recorder.record("list_folder", "stage") { AskToolResult(text: "b", ok: false) }
        #expect(recorder.calls.map(\.id) == [1, 2])
        #expect(recorder.calls.map(\.name) == ["vault_summary", "list_folder"])
        #expect(recorder.calls[1].ok == false)
    }
}
