import Foundation
import Testing
@testable import VoiceDebrief

/// A screenshot sent to a recipient: the picture in parts, then the line typed with it.
struct PictureMessageTests {
    private func header(_ message: Data) throws -> DeveloperLane.Header {
        let line = message.prefix { $0 != 0x0A }
        return try JSONDecoder().decode(DeveloperLane.Header.self, from: line)
    }

    @Test func pictureThenText() throws {
        let picture = Data(repeating: 7, count: DeveloperLane.partSize + 10)
        let messages = try DeveloperLane.imageMessages(image: picture, imageName: "screenshot.jpg", caption: "  look at this \n",
                                                       id: "picture-1", app: "test", at: Date(timeIntervalSince1970: 0))
        #expect(messages.count == 3)
        let first = try header(messages[0])
        #expect(first.kind == "voicedebrief/image/v1")
        #expect(first.part == 1 && first.of == 2 && first.size == picture.count && first.note == "picture-1")
        let text = try header(messages[2])
        #expect(text.kind == "voicedebrief/text/v1" && text.name == "message.txt")
        #expect(messages[2].split(separator: 0x0A, maxSplits: 1)[1] == Data("look at this".utf8))
    }

    @Test func noTextNoTextMessage() throws {
        let messages = try DeveloperLane.imageMessages(image: Data([1, 2, 3]), imageName: "s.jpg", caption: "   ",
                                                       id: "p", app: "t", at: Date())
        #expect(messages.count == 1)
    }
}
