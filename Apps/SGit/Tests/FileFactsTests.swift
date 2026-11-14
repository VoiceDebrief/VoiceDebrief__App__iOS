import Foundation
import Testing
import UIKit
@testable import SGit

@Suite("A small picture and the facts, kept beside each file")
struct FileFactsTests {
    private func photo() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "facts-\(UUID().uuidString).jpg")
        try #require(image.jpegData(compressionQuality: 0.8)).write(to: url)
        return url
    }

    @Test func aPhotoGetsASmallPictureAndItsSize() async throws {
        let url = try photo()
        let made = await FileFacts.make(for: url, name: "IMG_1.jpg", size: 1234, contentHash: "abc123def456",
                                        contentType: "image/jpeg", keepLocation: false,
                                        at: Date(timeIntervalSince1970: 1_800_000_000))
        let thumb = try #require(made.thumb.flatMap(UIImage.init(data:)))
        #expect(max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale) <= CGFloat(FileFacts.thumbPixels))
        let meta = try #require(made.meta.flatMap(FileMeta.decode))
        #expect(meta.kind == "image")
        #expect(meta.contentHash == "abc123def456")
        #expect(meta.image?.width != nil)
        #expect(meta.location == nil)
        #expect(meta.header?.keys.contains { $0.contains("GPS") } != true)
    }

    @Test func theLayoutIsKeyedByContentAndHiddenFromBrowsing() {
        #expect(FileFacts.thumbPath("abc") == ".sgit/thumbs/abc.jpg")
        #expect(FileFacts.metaPath("abc") == ".sgit/meta/abc.json")
        let paths = [".sgit/thumbs/abc.jpg", "secrets/.my-secrets", "secrets/1234.json", "trip/a.jpg", "README.md"]
        #expect(paths.filter(VaultListing.isVisible) == ["trip/a.jpg", "README.md"])
    }

    @Test func aQuickTimeLocationIsRead() throws {
        let place = try #require(FileMeta.Location(iso6709: "+38.7223-009.1393+045.000/"))
        #expect(place.latitude == 38.7223)
        #expect(place.longitude == -9.1393)
        #expect(place.altitude == 45)
        #expect(FileMeta.Location(iso6709: "nowhere") == nil)
    }

    @Test func aLengthAndASizeAreSaidPlainly() {
        var meta = FileMeta(name: "a.mov", size: 1, contentHash: "x", contentType: "video/quicktime", kind: "video",
                            addedAt: Date(timeIntervalSince1970: 0))
        meta.video = FileMeta.Video(durationSeconds: 125.4, width: 1920, height: 1080, codec: "hvc1")
        let lines = Dictionary(uniqueKeysWithValues: meta.lines)
        #expect(lines["Length"] == "2:05")
        #expect(lines["Dimensions"] == "1920 × 1080")
        #expect(lines["Codec"] == "hvc1")
    }
}
