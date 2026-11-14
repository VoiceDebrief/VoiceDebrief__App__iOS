import Foundation
import SGitPeople
import Testing
@testable import SGit

@Suite("People in the sgit app")
@MainActor
struct PeopleModelTests {
    @Test func nothingIsMadeUntilAskedThenTheKeysAreKept() async throws {
        let cloud = MemoryCloudKeychain()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("people-\(UUID().uuidString)")
        let model = PeopleModel(peopleKeychain: MemoryKeychain(cloud: cloud), secretsKeychain: MemoryKeychain(), folder: folder)
        #expect(!model.hasIdentity)
        #expect(model.unreadCount == 0)
        await model.makeIdentity(name: "Ana")
        #expect(model.hasIdentity)
        #expect(model.hub?.myCard?.name == "Ana")
        #expect(model.hub?.myCard?.inbox == nil)
        // Another device on the same iCloud account opens as the same person, with nothing made.
        let other = PeopleModel(peopleKeychain: MemoryKeychain(cloud: cloud), secretsKeychain: MemoryKeychain(), folder: nil)
        #expect(other.hub?.identity.bundle.fingerprint == model.hub?.identity.bundle.fingerprint)
    }
}
