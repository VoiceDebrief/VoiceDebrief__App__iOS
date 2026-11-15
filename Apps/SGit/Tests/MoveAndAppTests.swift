import Foundation
import Testing
@testable import SGit

@Suite("Moving files in one change, and opening a vault's own app")
struct MoveAndAppTests {
    private let all = ["stage/a.jpg", "stage/b.jpg", "stage/day1/c.jpg", "photos/a.jpg", "README.md", ".sgit/meta/x.json"]

    @Test func filesAndAFolderMoveTogetherKeepingTheirShape() {
        let plan = MovePlan.make(files: ["stage/b.jpg"], folders: ["stage/day1"], to: "photos/day-2", all: all, rename: false)
        #expect(plan.clashes.isEmpty)
        #expect(plan.steps == [.init(from: "stage/b.jpg", to: "photos/day-2/b.jpg"),
                               .init(from: "stage/day1/c.jpg", to: "photos/day-2/day1/c.jpg")])
        #expect(plan.message == "Move 2 files to photos/day-2")
    }

    @Test func aClashIsRefusedUnlessRenamed() {
        let refused = MovePlan.make(files: ["stage/a.jpg"], folders: [], to: "photos", all: all, rename: false)
        #expect(refused.steps.isEmpty)
        #expect(refused.clashes == ["a.jpg"])
        let renamed = MovePlan.make(files: ["stage/a.jpg"], folders: [], to: "photos", all: all, rename: true)
        #expect(renamed.clashes.isEmpty)
        #expect(renamed.steps.first?.to != "photos/a.jpg")
        #expect(renamed.steps.first?.to.hasPrefix("photos/a") == true)
        #expect(renamed.message == "Move a.jpg to photos")
    }

    @Test func aFolderCannotGoInsideItselfAndStayingPutIsNoMove() {
        #expect(MovePlan.make(files: [], folders: ["stage"], to: "stage/day1", all: all, rename: false).steps.isEmpty)
        #expect(MovePlan.make(files: ["stage/a.jpg"], folders: [], to: "stage", all: all, rename: false).steps.isEmpty)
        #expect(MovePlan.make(files: ["README.md"], folders: [], to: "", all: all, rename: false).steps.isEmpty)
        #expect(MovePlan.make(files: ["stage/a.jpg"], folders: [], to: "", all: all, rename: false).message == "Move a.jpg to the top of the vault")
    }

    @Test func aVaultOpensInItsOwnAppWhenItHasOne() {
        #expect(WebVault.start(for: ["app.json", "index.html"], path: "").surface == .app)
        #expect(WebVault.start(for: [".vault/app.json"], path: "").surface == .app)
        let page = WebVault.start(for: ["index.html", "a.jpg"], path: "")
        #expect(page.surface == .files)
        #expect(page.path == "index.html")
        #expect(WebVault.start(for: ["a.jpg"], path: "").surface == .files)
        #expect(WebVault.start(for: nil, path: "").surface == .app)
        let file = WebVault.start(for: ["app.json"], path: "notes/a.md")
        #expect(file.surface == .files)
        #expect(file.path == "notes/a.md")
        #expect(WebVault.Surface.app.address.path() == "/en-gb/app/")
        #expect(WebVault.Surface.files.mode == "vault")
    }

    @Test func leavingEmbedModeIsNoticed() {
        #expect(WebVault.leftEmbed(URL(string: "https://dev.vault.sgraph.ai/en-gb/vault/")))
        #expect(!WebVault.leftEmbed(URL(string: "https://dev.vault.sgraph.ai/en-gb/vault/?embed=1")))
        #expect(!WebVault.leftEmbed(URL(string: "https://dev.vault.sgraph.ai/en-gb/app/?embed=1")))
        #expect(!WebVault.leftEmbed(URL(string: "https://example.com/en-gb/vault/")))
    }

    @Test func theGalleryPageFollowsTheVaultAppContract() throws {
        let html = String(decoding: GalleryPage.html(title: "Web <Summit>"), as: UTF8.self)
        #expect(html.contains("sg.vfs.readText('gallery.json')"))
        #expect(html.contains("type: 'sg-app-ready'"))
        #expect(html.contains("sg.vfs.read(item.path)"))
        #expect(!html.contains("fetch("))
        #expect(!html.contains("<script src"))
        #expect(html.contains("Web &lt;Summit>"))
        let app = try #require(try JSONSerialization.jsonObject(with: try GalleryPage.app(title: "T")) as? [String: Any])
        #expect(app["entry"] as? String == "index.html")
        #expect(app["present"] as? Bool == true)
    }
}
