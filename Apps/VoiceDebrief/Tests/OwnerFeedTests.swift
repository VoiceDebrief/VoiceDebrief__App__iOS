import Foundation
import Testing
@testable import VoiceDebrief

@Suite("Owner mode: the feed")
struct OwnerFeedTests {
    static func feed(_ json: String) throws -> OwnerFeed { try OwnerFeed.decode(Data(json.utf8)) }

    static let small = """
    {"kind":"owner.feed/v1","made":"2026-11-23T18:00:00Z","by":"test",
     "agents":[{"id":"m","name":"Maestro","kind":"maestro","status":"working","doing":"a brief"},
               {"id":"s","name":"Sub","kind":"subagent","status":"done","doing":"a check"},
               {"id":"a","name":"Agent","kind":"agent","status":"waiting","doing":"CI","waitingFor":"green"}],
     "sites":[{"id":"x","title":"A site","url":"https://example.com/","agent":"a","made":"2026-11-23T17:00:00Z"}],
     "decisions":[{"id":"d","title":"Pick","options":["Yes","No"],"from":"m","at":"2026-11-23T17:30:00Z"}]}
    """

    @Test func theTwinIsBundledAndKeepsTheContract() throws {
        let twin = try #require(OwnerFeed.bundledTwin())
        #expect(twin.twin == true)
        #expect(twin.kind == OwnerFeed.kind)
        #expect(!twin.agents.isEmpty)
        #expect(!(twin.decisions ?? []).isEmpty)
        // Every address in the twin leads nowhere real.
        for item in twin.allItems { #expect(item.url.hasPrefix("https://example.com/")) }
        for agent in twin.agents { if let site = agent.site { #expect(site.hasPrefix("https://example.com/")) } }
    }

    @Test func aFeedReadsAndSortsAgentsFromTheBiggest() throws {
        let feed = try Self.feed(Self.small)
        #expect(feed.agentsBySize.map(\.id) == ["m", "a", "s"])
        #expect(feed.agent("a")?.waitingFor == "green")
        #expect(feed.allItems.count == 1)
    }

    @Test func anotherKindIsRefused() {
        #expect(throws: OwnerFeed.FeedError.wrongKind("agents/v1")) {
            try Self.feed(Self.small.replacingOccurrences(of: "owner.feed/v1", with: "agents/v1"))
        }
    }

    @Test func anItemFromAnUnlistedAgentIsRefused() {
        #expect(throws: OwnerFeed.FeedError.unknownAgent("ghost")) {
            try Self.feed(Self.small.replacingOccurrences(of: "\"agent\":\"a\"", with: "\"agent\":\"ghost\""))
        }
    }

    @Test func aRepeatedIdIsRefused() {
        #expect(throws: OwnerFeed.FeedError.repeatedId("m")) {
            try Self.feed(Self.small.replacingOccurrences(of: "\"id\":\"d\"", with: "\"id\":\"m\""))
        }
    }

    @Test func aDecisionNeedsTwoChoices() {
        #expect(throws: OwnerFeed.FeedError.noOptions("d")) {
            try Self.feed(Self.small.replacingOccurrences(of: "[\"Yes\",\"No\"]", with: "[\"Yes\"]"))
        }
    }

    @Test func anAnswerSaysWhichDecisionAndWhichChoice() throws {
        let feed = try Self.feed(Self.small)
        let decision = try #require(feed.decisions?.first)
        let out = OwnerOutgoing.answer(decision, choice: "No", app: "0.1 (1)", at: Date(timeIntervalSince1970: 0), id: "o1")
        let json = try #require(String(data: try out.encoded(), encoding: .utf8))
        #expect(json.contains("\"kind\":\"owner.answer\\/v1\""))
        #expect(json.contains("\"decision\":\"d\""))
        #expect(json.contains("\"choice\":\"No\""))
        #expect(json.contains("\"to\":\"m\""))
    }

    @Test func aMessageAboutAPageCarriesThePage() throws {
        let feed = try Self.feed(Self.small)
        let item = try #require(feed.sites?.first)
        let out = OwnerOutgoing.message(about: item, to: item.agent, text: "Make it green", app: "0.1 (1)", at: Date(timeIntervalSince1970: 0), id: "o2")
        #expect(out.kind == OwnerOutgoing.messageKind)
        #expect(out.page == "https://example.com/")
        #expect(out.pageTitle == "A site")
        #expect(out.text == "Make it green")
    }

    @MainActor @Test func demoAnswersAreKeptAndNeverSent() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "owner-\(UUID().uuidString)")
        let desk = OwnerDesk(folder: folder)
        desk.source = .demo
        let twin = try #require(OwnerFeed.bundledTwin())
        let decision = try #require(twin.decisions?.first)
        await desk.answer(decision, with: decision.options[0])
        #expect(desk.decisions.last?.delivery == "Not sent: demo")
        await desk.talk(about: twin.sites?.first, to: twin.agents[0].id, text: "Make it green")
        #expect(desk.actions.last?.kind == "talk-to-page")
        #expect(desk.actions.last?.delivery == "Not sent: demo")
        // Decisions and actions are kept apart, and both survive a new desk on the same folder.
        let again = OwnerDesk(folder: folder)
        #expect(again.decisions.count == 1)
        #expect(again.actions.count == 1)
    }
}
