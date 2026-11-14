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
    static func parts(_ s: AvatarSeed) -> [Int] { [s.colour, s.shape, s.eyes, s.mouth, s.accent] }

    @Test func knownIdsDrawKnownCharacters() {
        let conductor: [Int] = [8, 2, 2, 0, 2]
        let me: [Int] = [4, 3, 0, 1, 8]
        #expect(Self.parts(AvatarSeed(id: "conductor")) == conductor)
        #expect(Self.parts(AvatarSeed(id: "me")) == me)
    }

    @Test func anotherVariantIsAnotherLook() {
        let expected: [Int] = [11, 0, 2, 2, 5]
        #expect(Self.parts(AvatarSeed(id: "conductor", variant: 1)) == expected)
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
