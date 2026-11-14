import Foundation
import Testing
@testable import VoiceDebrief

@Suite("A character drawn from an id")
struct AvatarSeedTests {
    @Test func theSameIdDrawsTheSameCharacter() {
        #expect(AvatarSeed(id: "agent-7") == AvatarSeed(id: "agent-7"))
    }

    /// Worked out independently with Python's hashlib (SHA-256 of "conductor#0" and "me#0"), so the
    /// character is the same on any device and in any later build.
    @Test func knownIdsDrawKnownCharacters() {
        let c = AvatarSeed(id: "conductor")
        #expect([c.colour, c.shape, c.eyes, c.mouth, c.accent] == [8, 2, 2, 0, 2])
        let me = AvatarSeed(id: "me")
        #expect([me.colour, me.shape, me.eyes, me.mouth, me.accent] == [4, 3, 0, 1, 8])
    }

    @Test func anotherVariantIsAnotherLook() {
        let c = AvatarSeed(id: "conductor", variant: 1)
        #expect([c.colour, c.shape, c.eyes, c.mouth, c.accent] == [11, 0, 2, 2, 5])
    }

    @Test func theAccentIsNeverTheMainColourOrItsNeighbour() {
        for i in 0..<200 {
            let s = AvatarSeed(id: "id-\(i)")
            let gap = (s.accent - s.colour + AvatarSeed.palette.count) % AvatarSeed.palette.count
            #expect((3...8).contains(gap))
        }
    }

    @Test func manyIdsUseMostOfThePalette() {
        let colours = Set((0..<200).map { AvatarSeed(id: "fp-\($0)").colour })
        #expect(colours.count >= 10)
    }

    @Test func agentKindsAreRead() {
        #expect(AvatarKind(agentKind: "conductor") == .conductor)
        #expect(AvatarKind(agentKind: "subagent") == .subagent)
        #expect(AvatarKind(agentKind: "session") == .session)
        #expect(AvatarKind(agentKind: "something new") == .session)
        #expect(AvatarKind.conductor.isAgent && !AvatarKind.me.isAgent)
    }
}

@Suite("The names under a route")
struct RouteNamesTests {
    @Test func namesAreSaidPlainly() {
        #expect(RouteNames.line([]) == "")
        #expect(RouteNames.line(["Sam"]) == "Sam")
        #expect(RouteNames.line(["Sam", "Ana"]) == "Sam and Ana")
        #expect(RouteNames.line(["Sam", "Ana", "Jo"]) == "Sam, Ana and Jo")
        #expect(RouteNames.line(["Sam", "Ana", "Jo", "Lu", "Max"]) == "Sam, Ana and 3 more")
    }
}
