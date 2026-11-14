import Foundation
import Testing
@testable import SGit

@Suite("Names, paths and messages")
struct NamingTests {
    @Test func aTakenNameGetsANumberBeforeItsExtension() {
        #expect(VaultNaming.unique("a.jpg", taken: []) == "a.jpg")
        #expect(VaultNaming.unique("a.jpg", taken: ["a.jpg"]) == "a 2.jpg")
        #expect(VaultNaming.unique("a.jpg", taken: ["a.jpg", "a 2.jpg"]) == "a 3.jpg")
        #expect(VaultNaming.unique("README", taken: ["README"]) == "README 2")
        #expect(VaultNaming.unique(".hidden", taken: [".hidden"]) == ".hidden 2")
    }

    @Test func aSelectionGetsPathsThatCollideWithNothing() {
        let paths = VaultNaming.paths(for: ["IMG_1.HEIC", "IMG_1.HEIC", "a/b.txt", ""], in: "trip",
                                      existing: ["trip/IMG_1.HEIC", "trip/deep/IMG_1 2.HEIC", "IMG_1 2.HEIC"])
        #expect(paths == ["trip/IMG_1 2.HEIC", "trip/IMG_1 3.HEIC", "trip/a-b.txt", "trip/file"])
        #expect(VaultNaming.paths(for: ["x.mov"], in: "", existing: ["x.mov"]) == ["x 2.mov"])
    }

    @Test func namesAndFoldersAreMadeSafe() {
        #expect(!VaultNaming.clean("../x").contains("/"))
        #expect(!VaultNaming.clean("..").hasPrefix("."))
        #expect(VaultNaming.clean("") == "file")
        #expect(VaultNaming.cleanFolder(" a//b/ c ") == "a/b/c")
        #expect(VaultNaming.cleanFolder("///") == "")
    }

    @Test func theCommitMessageIsTheWebVaultsWording() {
        #expect(VaultNaming.addMessage(["a.jpg"]) == "Add a.jpg")
        #expect(VaultNaming.addMessage(["a", "b", "c"]) == "Add 3 files: a, b, c")
        #expect(VaultNaming.addMessage(["a", "b", "c", "d"]) == "Add 4 files: a, b, c…")
        let long = VaultNaming.addMessage([String(repeating: "x", count: 2_000)])
        #expect(long.utf8.count <= 740)
    }

    @Test func aScannedLinkGivesItsKey() {
        #expect(VaultNaming.keyText(from: "  some-pass:abcd1234 \n") == "some-pass:abcd1234")
        #expect(VaultNaming.keyText(from: "https://vault.sgraph.ai/#some-pass:abcd1234") == "some-pass:abcd1234")
        #expect(VaultNaming.keyText(from: "https://vault.sgraph.ai/#some-pass:abcd1234|photos/a.jpg") == "some-pass:abcd1234")
        #expect(VaultNaming.keyText(from: "https://vault.sgraph.ai/#some%20pass:abcd1234") == "some pass:abcd1234")
    }

    @Test func onlyAVaultKeyBecomesAWebLink() {
        #expect(VaultNaming.webLink(keyText: "some-pass:abcd1234") == "https://vault.sgraph.ai/#some-pass:abcd1234")
        let readKey = "sgit_private_read_" + String(repeating: "ab", count: 32) + ":abcd1234"
        #expect(VaultNaming.webLink(keyText: readKey) == nil)
    }

    @Test func fingerprintsAndSizesAreReadable() {
        #expect(VaultNaming.grouped("a1b2c3d4e5f60718") == "a1b2 c3d4 e5f6 0718")
        #expect(2_370_000_000.fileSizeText == "2.37 GB")
        #expect(4_100_000.fileSizeText == "4.1 MB")
    }

    @Test func theFoldersMakeATree() {
        let tree = VaultListing.tree(paths: ["a.txt", "trip/day 2/x.jpg", "trip/day 10/y.jpg", "trip/z.mov", "notes/n.md"])
        #expect(tree.map(\.path) == ["notes", "trip"])
        #expect(tree[0].children == nil)
        #expect(tree[1].children?.map(\.path) == ["trip/day 2", "trip/day 10"])
        #expect(VaultListing.tree(paths: ["only.txt"]).isEmpty)
    }

    @Test func aShowcaseFileIsReadInEitherShape() {
        let whole = Data(#"{"v":1,"entries":[{"name":"Costs","description":"What it costs to run","topic":"Running it","link":"https://vault.sgraph.ai/#ro-quiet-river-1234"},{"link":"  "},{"link":"some-pass:abcd1234"}]}"#.utf8)
        let entries = Gallery.entries(in: whole)
        #expect(entries.map(\.name) == ["Costs", "A vault"])
        #expect(entries[0].topic == "Running it")
        let bare = Data(#"[{"name":"Setup","link":"some-pass:abcd1234"}]"#.utf8)
        #expect(Gallery.entries(in: bare).map(\.name) == ["Setup"])
        #expect(Gallery.entries(in: Data("not json".utf8)).isEmpty)
        #expect(Gallery.entries(in: Gallery.file(entries)) == entries)
    }

    @Test func anEntryOpensInTheWebVault() {
        #expect(Gallery.webAddress(of: "https://dev.vault.sgraph.ai/#some-pass:abcd1234")?.absoluteString == "https://dev.vault.sgraph.ai/#some-pass:abcd1234")
        #expect(Gallery.webAddress(of: "some-pass:abcd1234")?.absoluteString == "https://vault.sgraph.ai/#some-pass:abcd1234")
        #expect(Gallery.webAddress(of: "ro-quiet-river-1234")?.absoluteString == "https://vault.sgraph.ai/#ro-quiet-river-1234")
        let hex = String(repeating: "ab", count: 32)
        #expect(Gallery.webAddress(of: "sgit_private_read_" + hex + ":abcd1234")?.absoluteString == "https://vault.sgraph.ai/#" + hex + ":abcd1234")
        // Never plain http, and never nothing.
        #expect(Gallery.webAddress(of: "http://example.com/#x") == nil)
        #expect(Gallery.webAddress(of: "  ") == nil)
    }

    @Test func onlyAKeyCanBeAddedToMyVaults() {
        #expect(Gallery.nativeKey(of: "some-pass:abcd1234") == "some-pass:abcd1234")
        #expect(Gallery.nativeKey(of: "https://vault.sgraph.ai/#some-pass:abcd1234|notes/a.md") == "some-pass:abcd1234")
        #expect(Gallery.nativeKey(of: "ro-quiet-river-1234") == nil)
        #expect(Gallery.nativeKey(of: "https://vault.sgraph.ai/#ro-quiet-river-1234") == nil)
        #expect(Gallery.nativeKey(of: "https://example.com/page") == nil)
    }

    @Test func theGalleryIsGroupedAndSearched() {
        let entries = [GalleryEntry(name: "Zebra", topic: "Animals", link: "a:aaaa1111"),
                       GalleryEntry(name: "Costs", description: "What it costs", topic: "Running it", link: "b:bbbb1111"),
                       GalleryEntry(name: "Ant", topic: "Animals", link: "c:cccc1111"),
                       GalleryEntry(name: "Loose", link: "d:dddd1111"),
                       GalleryEntry(name: "Ant again", topic: "Animals", link: "c:cccc1111")]
        let groups = Gallery.grouped(entries)
        #expect(groups.map(\.topic) == ["Animals", "Running it", ""])
        #expect(groups[0].entries.map(\.name) == ["Ant", "Zebra"])
        #expect(Gallery.grouped(entries, search: "costs").map(\.topic) == ["Running it"])
        #expect(Gallery.grouped(entries, search: "nothing like it").isEmpty)
    }

    @Test func aFileIsKnownByItsName() {
        #expect(VaultListing.kind(of: "a/IMG_1.HEIC") == .image)
        #expect(VaultListing.kind(of: "clip.MOV") == .video)
        #expect(VaultListing.kind(of: "voice.m4a") == .audio)
        #expect(VaultListing.kind(of: "notes.md") == .document)
        #expect(VaultListing.name(of: "a/b/c.txt") == "c.txt")
        #expect(VaultListing.parent(of: "a/b/c.txt") == "a/b")
        #expect(VaultListing.parent(of: "c.txt") == "")
    }
}
