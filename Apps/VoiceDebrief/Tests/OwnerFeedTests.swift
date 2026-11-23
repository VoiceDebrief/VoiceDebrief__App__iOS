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

    @Test func anItemFromAnUnlistedAgentIsKeptAndSaid() throws {
        let feed = try Self.feed(Self.small.replacingOccurrences(of: "\"agent\":\"a\"", with: "\"agent\":\"ghost\""))
        #expect(feed.sites?.count == 1)
        #expect(feed.problems.contains { $0.contains("ghost") })
    }

    @Test func aRepeatedIdKeepsTheFirst() throws {
        let feed = try Self.feed(Self.small.replacingOccurrences(of: "\"id\":\"s\"", with: "\"id\":\"m\""))
        #expect(feed.agents.filter { $0.id == "m" }.count == 1)
        #expect(feed.agent("m")?.name == "Maestro")
        #expect(feed.problems.contains { $0.contains("m is listed twice") })
    }

    @Test func aDecisionWithOneChoiceIsLeftOutAndSaid() throws {
        let feed = try Self.feed(Self.small.replacingOccurrences(of: "[\"Yes\",\"No\"]", with: "[\"Yes\"]"))
        #expect(feed.decisions?.isEmpty == true)
        #expect(feed.problems.contains { $0.contains("fewer than two choices") })
    }

    @Test func aRowThatCannotBeReadIsLeftOutNotTheFeed() throws {
        let feed = try Self.feed(Self.small.replacingOccurrences(of: "{\"id\":\"s\",\"name\":\"Sub\",", with: "{\"id\":\"s\","))
        #expect(feed.agents.count == 2)
        #expect(feed.problems.contains { $0.contains("1 of 3 in agents") })
    }

    /// A recorded feed: d.holacracy's team index of account D (PrompTugal__News__Website, board/team/holacracy.d/
    /// team-index.json at 3811d596a), relayed by a.maestro on 23 November 2026: its header and one entry of every
    /// shape, verbatim except that the session addresses are replaced by session_REDACTED.
    static let teamIndex = #"""
    {
     "kind": "owner.feed/v1",
     "made": "2026-11-23T20:53:00Z",
     "by": "d.holacracy (account-d)",
     "twin": false,
     "about": "The team index of account D, from the governance record (org-chart.json), drawn by a script. Account D is seen; the other accounts are reported, not seen. Status and times are as read at the date in each row; they are not live.",
     "extra_fields": ["circle","lead","session","model","home","homeUrl","repo","relayed","proposed"],
     "agents": [
      {"id": "d.maestro.account-d","name": "d.maestro (account-d)","account": "D","kind": "maestro","status": "working","doing": "working","circle": "maestros","session": "https://claude.ai/code/session_REDACTED","model": "opus","home": "SovereignWebsite/Site__Agent__Maestro","updated": "2026-11-23T16:48:55Z","relayed": true,"homeUrl": "https://github.com/SovereignWebsite/Site__Agent__Maestro"},
      {"id": "d.hub.SovereignWebsite","name": "d.hub (SovereignWebsite)","account": "D","kind": "agent","status": "waiting","doing": "waiting on Dinis: merge work/hub.d-r2?","circle": "SovereignWebsite","lead": "d.conductor (SovereignWebsite)","parent": "d.maestro.account-d","waitingFor": "Dinis: merge work/hub.d-r2?","session": "https://claude.ai/code/session_REDACTED","model": "sonnet","home": "SovereignWebsite/Site__Agent__Hub","updated": "2026-11-23T16:51:57Z","relayed": true,"homeUrl": "https://github.com/SovereignWebsite/Site__Agent__Hub"},
      {"id": "d.bulletins.PrompTugal","name": "d.bulletins (PrompTugal)","account": "D","kind": "agent","status": "waiting","doing": "review ready","circle": "PrompTugal","lead": "d.conductor (PrompTugal)","parent": "d.conductor.PrompTugal","waitingFor": "review","session": "https://claude.ai/code/session_REDACTED","model": "opus","repo": "PrompTugal/PrompTugal__News__Bulletins","updated": "2026-11-23T05:08:12Z","relayed": true},
      {"id": "d.decisions.account-d","name": "d.decisions (account-d)","account": "D","kind": "signer","status": "working","doing": "working","circle": "central","lead": "d.helm (account-d)","parent": "d.maestro.account-d","session": "https://claude.ai/code/session_REDACTED","home": "SovereignWebsite/Site__Agent__Decisions","updated": "2026-11-23T16:52:18Z","relayed": true,"proposed": true,"homeUrl": "https://github.com/SovereignWebsite/Site__Agent__Decisions"},
      {"id": "studio.director.d","name": "studio.director","account": "D","kind": "subagent","parent": "d.studio.account-d","status": "unknown","doing": "a sub-agent inside d.studio's run (named in helm.d's role file, relayed); not a session of its own","relayed": true}
     ],
     "reported_not_seen": [
      {"id": "b.decisions","name": "b.decisions (SovereignWebsite)","account": "B","kind": "signer","session": "https://claude.ai/code/session_REDACTED","source": "board/team/maestro.b/decisions/2026-11-23-account-prefix-first.md","as_of": "2026-11-23T13:00Z"}
     ],
     "sites": [], "videos": [], "briefs": [], "slides": [],
     "decisions": [
      {"id": "D10","title": "How an agent's key reaches its home's Factory key list","detail": "A home asks for a commit signed with a key published in the Factory's team/keys.json. The Factory's own rule says that file waits for Dinis's merge; helm.d relays that each agent publishes its own by a signed commit of its own; CLAUDE.md's no-agent-blocked rule lists 'making and publishing your own key by your own signed commit' as an own-area step.","options": ["A. Keys go by branch, Dinis merges each (the Factory's current rule)","B. Self-published keys: an agent lands its own key by its own signed commit","C. Keys stay in each project's own keys file until homes need them"],"recommended": "B","from": "d.holacracy","at": "2026-11-23T17:10Z","evidence": ["board/team/holacracy.d/MOVE-TO-HOME.md"],"lane": "d.decisions"}
     ]
    }
    """#

    @Test func theRecordedTeamIndexReads() throws {
        let feed = try OwnerFeed.decode(Data(Self.teamIndex.utf8))
        #expect(feed.twin == false)
        #expect(feed.agents.count == 5)
        #expect(feed.agentsBySize.first?.kind == "maestro")
        #expect(feed.agent("d.hub.SovereignWebsite")?.waitingFor == "Dinis: merge work/hub.d-r2?")
        #expect(feed.agent("d.hub.SovereignWebsite")?.homeUrl == "https://github.com/SovereignWebsite/Site__Agent__Hub")
        #expect(feed.agent("d.bulletins.PrompTugal")?.repo == "PrompTugal/PrompTugal__News__Bulletins")
        #expect(feed.agent("d.decisions.account-d")?.proposed == true)
        #expect(feed.agent("studio.director.d")?.status == "unknown")
        #expect(feed.reported_not_seen?.first?.account == "B")
        // A time without seconds is still a time.
        let decision = try #require(feed.decisions?.first)
        #expect(decision.at == OwnerFeed.date("2026-11-23T17:10:00Z"))
        #expect(decision.recommendedOptions == ["B. Self-published keys: an agent lands its own key by its own signed commit"])
        // Its asker is named by a short name, not an id in the list: kept, and said.
        #expect(feed.problems.contains { $0.contains("d.holacracy") })
    }

    @MainActor @Test func publishedFeedsAreReadTogetherAndABrokenOneIsSaid() async throws {
        let twin = try #require(Bundle.main.url(forResource: OwnerFeed.twinResource, withExtension: "json"))
        let twinData = try Data(contentsOf: twin)
        let index = Data(Self.teamIndex.utf8)
        let feed = try #require(await OwnerDesk.readPublished(["https://a.example/index.json", "https://b.example/twin.json", "https://c.example/broken.json"]) { url in
            switch url.host {
            case "a.example": return index
            case "b.example": return twinData
            default: return Data("not json".utf8)
            }
        })
        #expect(feed.agents.count == 5 + (OwnerFeed.bundledTwin()?.agents.count ?? 0))
        #expect(feed.problems.contains { $0.contains("broken.json") })
    }

    @Test func aCombinedRecommendationNamesEachOption() {
        let decision = OwnerFeed.Decision(id: "x", title: "t", options: ["A. one", "B. two", "C. three"], from: "m",
                                          at: Date(), recommended: "AB")
        #expect(decision.recommendedOptions == ["A. one", "B. two"])
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
