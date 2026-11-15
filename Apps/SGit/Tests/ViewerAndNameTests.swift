import Foundation
import Testing
@testable import SGit

struct ViewerAndNameTests {
    @Test func theVaultsOwnNameIsReadFromItsSettings() {
        let data = Data(#"{"vault_name": "  Summit RM team - Raw image upload ", "vault_id": "5min3g7g", "created": "2026-11-15T19:05:58.813Z", "version": 2}"#.utf8)
        #expect(VaultSettings.name(in: data) == "Summit RM team - Raw image upload")
        #expect(VaultSettings.name(in: Data(#"{"vault_name": ""}"#.utf8)) == nil)
        #expect(VaultSettings.name(in: Data(#"{"vault_id": "x"}"#.utf8)) == nil)
        #expect(VaultSettings.name(in: Data("not json".utf8)) == nil)
        #expect(!VaultListing.isVisible(VaultSettings.path))
    }

    @Test func theTreeKeepsOpenEveryFolderAboveTheOneShown() {
        #expect(FolderTree.above("dinis/movies/day-2") == ["dinis/movies/day-2", "dinis/movies", "dinis"])
        #expect(FolderTree.above("").isEmpty)
    }

    @Test func photosAndVideosOpenInTheViewerAndOtherFilesDoNot() {
        #expect(PictureViewer.shows("dinis/IMG_1316.heic"))
        #expect(PictureViewer.shows("dinis/movies/IMG_1339.mov"))
        #expect(!PictureViewer.shows("notes/plan.pdf"))
        #expect(!PictureViewer.shows("index.html"))
    }
}
