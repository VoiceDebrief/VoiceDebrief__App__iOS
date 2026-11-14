import CoreGraphics
import Foundation
import Testing
@testable import SGit

@Suite("The trust map and shared vaults")
struct TeamTests {
    @Test func aLineIsAsStrongAsBothSidesMadeIt() {
        #expect(TrustLink.of(isMutual: true, verified: true) == .verified)
        #expect(TrustLink.of(isMutual: true, verified: false) == .mutual)
        #expect(TrustLink.of(isMutual: false, verified: true) == .oneWay)
        #expect(TrustLink.of(isMutual: false, verified: false) == .oneWay)
    }

    @Test func peopleAreSpacedRoundYouStartingAtTheTop() {
        let places = TrustLayout.positions(count: 4, in: CGSize(width: 400, height: 400), inset: 50)
        #expect(places.count == 4)
        #expect(abs(places[0].x - 200) < 0.001)
        #expect(abs(places[0].y - 50) < 0.001)
        #expect(abs(places[1].x - 350) < 0.001)
        #expect(TrustLayout.positions(count: 0, in: CGSize(width: 10, height: 10)).isEmpty)
    }

    @Test func theMapSaysWhoIsWaiting() {
        let people = [
            TrustPerson(id: "a", name: "Ana", link: .verified, met: "", isAgent: false, canReceive: true),
            TrustPerson(id: "b", name: "Ben", link: .oneWay, met: "", isAgent: false, canReceive: false),
            TrustPerson(id: "c", name: "Claude", link: .mutual, met: "", isAgent: true, canReceive: true),
        ]
        #expect(TrustLayout.summary(people) == "2 people and 1 agent: 2 linked both ways, 1 waiting for their side.")
    }

    @Test func membersAreListedOnceAndRoundTrip() throws {
        let start = VaultMembers(members: [.init(name: "Sam", fingerprint: "sha256:aaa", addedAt: Date(timeIntervalSince1970: 0), addedBy: "Sam")])
        let more = start.adding([("Ana", "sha256:bbb"), ("Sam", "sha256:aaa"), ("Ana", "sha256:bbb")], by: "Sam",
                                at: Date(timeIntervalSince1970: 100))
        #expect(more.members.map(\.name) == ["Sam", "Ana"])
        let back = try #require(VaultMembers.decode(try more.encoded()))
        #expect(back == more)
        #expect(VaultMembers.path == ".sgit/members.json")
        #expect(VaultMembers.decode(Data(#"{"format":"other","members":[]}"#.utf8)) == nil)
    }
}
