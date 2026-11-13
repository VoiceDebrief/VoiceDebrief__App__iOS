import UIKit
import XCTest

/// A picture of every screen, so that the people and agents who write this app can see it without
/// a Mac (issue 016). Run by `.github/workflows/screens.yml` with the scheme `VoiceDebriefScreens`,
/// on one iPhone and one iPad simulator, in light and in dark.
///
/// Each test launches the app with `-VDSampleData <set>` and `-VDScreen <id>` (see
/// `Sources/App/LaunchOptions.swift`): invented notes in a temporary folder, a vault book in
/// memory, no network, no microphone. A simulator has no speech model, no Apple Intelligence and
/// no passkeys, so every state that depends on them is shown from sample data.
///
/// One test per shot, so a crash on one screen cannot stop the others. The attachment's name is
/// the PNG's name: `<screen id>` or `<screen id>-empty`.
final class ScreensTests: XCTestCase {
    /// screens.yml expects one PNG per entry. Keep it equal to the test methods below.
    static let shots = [
        "record", "record-empty", "record.recording", "record.working",
        "library", "library-empty",
        "note.finished", "note.transcript", "note.interrupted", "note.working",
        "vaults", "vaults-empty", "vault.detail",
        "settings", "diagnostics", "traffic", "about",
    ]

    @MainActor func test01_record() { shoot("record") }
    @MainActor func test02_record_empty() { shoot("record", set: "empty") }
    @MainActor func test03_record_recording() { shoot("record.recording") }
    @MainActor func test04_record_working() { shoot("record.working") }
    @MainActor func test05_library() { shoot("library") }
    @MainActor func test06_library_empty() { shoot("library", set: "empty") }
    @MainActor func test07_note_finished() { shoot("note.finished") }
    @MainActor func test08_note_transcript() { shoot("note.transcript") }
    @MainActor func test09_note_interrupted() { shoot("note.interrupted") }
    @MainActor func test10_note_working() { shoot("note.working") }
    @MainActor func test11_vaults() { shoot("vaults") }
    @MainActor func test12_vaults_empty() { shoot("vaults", set: "empty") }
    @MainActor func test13_vault_detail() { shoot("vault.detail", wait: 8) }
    @MainActor func test14_settings() { shoot("settings") }
    @MainActor func test15_diagnostics() { shoot("diagnostics", wait: 5) }
    @MainActor func test16_traffic() { shoot("traffic", wait: 8) }
    @MainActor func test17_about() { shoot("about") }

    func testTheListMatchesTheTestMethods() {
        XCTAssertEqual(Self.shots.count, 17)
        XCTAssertEqual(Set(Self.shots).count, Self.shots.count)
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func shoot(_ screen: String, set: String = "full", wait: UInt32 = 3) {
        // Landscape on iPad: the size at which the layout has most room to go wrong. screens.yml
        // turns the PNG upright from its EXIF orientation (the capture is the portrait framebuffer).
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = XCUIApplication()
        // -vd.localeId is the app's own setting, given for this launch only: a simulator's speech
        // model reports no languages, and without one the record screen shows only that warning.
        app.launchArguments = ["-VDSampleData", set, "-VDScreen", screen, "-vd.localeId", "en-GB"]
        app.launch()
        sleep(wait)
        // The picture first: a slow accessibility query must not cost the screenshot. The whole
        // screen, not the app element, whose capture is cropped wrongly in landscape on iPad.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = set == "full" ? screen : "\(screen)-\(set)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let marker = app.descendants(matching: .any).matching(identifier: "vd.screen.\(screen)").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "The app did not open \(screen) from its launch arguments")
        app.terminate()
    }
}
