import UIKit
import XCTest

/// A picture of every screen of the sgit app, so that the people and agents who write it can see it
/// without a Mac. Run by `.github/workflows/sgit-app-screens.yml` with the scheme `SGitScreens`, on one
/// iPhone and one iPad simulator. Copied in approach from `Apps/VoiceDebrief/UITests/ScreensTests.swift`.
///
/// Each test launches the app with `-SGScreen <id>` and `-SGSampleData <set>` (see
/// `Sources/App/LaunchSample.swift`): an invented vault held in temporary folders, a Keychain in
/// memory, no network. Nothing in these pictures came from a server.
final class ScreensTests: XCTestCase {
    /// sgit-app-screens.yml expects one PNG per entry. Keep it equal to the test methods below.
    static let shots = ["vaults", "vaults-empty", "create", "add", "vault", "vault.folder", "vault.list",
                        "file", "share", "history", "commit", "settings"]

    @MainActor func test01_vaults() { shoot("vaults") }
    @MainActor func test02_vaults_empty() { shoot("vaults", set: "empty") }
    @MainActor func test03_create() { shoot("create") }
    @MainActor func test04_add() { shoot("add") }
    @MainActor func test05_vault() { shoot("vault", wait: 6) }
    @MainActor func test06_vault_folder() { shoot("vault.folder", wait: 6) }
    @MainActor func test07_vault_list() { shoot("vault.list", wait: 6) }
    @MainActor func test08_file() { shoot("file", wait: 6) }
    @MainActor func test09_share() { shoot("share") }
    @MainActor func test10_history() { shoot("history") }
    @MainActor func test11_commit() { shoot("commit", wait: 5) }
    @MainActor func test12_settings() { shoot("settings") }

    func testTheListMatchesTheTestMethods() {
        XCTAssertEqual(Self.shots.count, 12)
        XCTAssertEqual(Set(Self.shots).count, Self.shots.count)
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func shoot(_ screen: String, set: String = "full", wait: UInt32 = 4) {
        // Landscape on iPad: where the folder tree sits beside the files.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = XCUIApplication()
        app.launchArguments = ["-SGScreen", screen, "-SGSampleData", set,
                               "-AppleLanguages", "(en-GB)", "-AppleLocale", "en_GB"]
        app.launch()
        // The sample vault is made at launch (key derivation, a dozen files, three commits).
        let marker = app.descendants(matching: .any).matching(identifier: "sg.screen.\(screen)").firstMatch
        let opened = marker.waitForExistence(timeout: 40)
        sleep(wait)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = set == "full" ? screen : "\(screen)-\(set)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(opened, "The app did not open \(screen) from its launch arguments")
        app.terminate()
    }
}
