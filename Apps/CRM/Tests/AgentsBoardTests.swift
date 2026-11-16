import Foundation
import Testing
@testable import CRM

/// W11 on an invented report in the conductor's format (agents/agents.json): every name here is made up.
struct AgentsBoardTests {
    static let json = #"""
    {"v":1,"made":"2026-11-16T18:00:00Z","conductor":"c1",
     "agents":[
       {"id":"c1","name":"conductor.example","kind":"conductor","role":"routes the work","status":"working","doing":"Reading the board","group":"Example team","lastActive":"2026-11-16T17:59:00Z"},
       {"id":"a1","name":"writer.example","kind":"session","role":"writes","status":"idle","doing":"Nothing","group":"Example team"},
       {"id":"a2","name":"builder.example","kind":"session","role":"builds","status":"blocked","doing":"Waiting for a key","waitingFor":"the owner","group":"Example team","parent":"c1"},
       {"id":"a3","name":"reader.example","kind":"subagent","role":"reads","status":"working","doing":"Reading a vault","group":"Quiet team"}
     ],
     "links":[{"from":"c1","to":"a2","label":"brief"}],
     "messages":[
       {"id":"m1","agent":"c1","from":"c1","at":"2026-11-16T17:00:00Z","text":"Older"},
       {"id":"m2","agent":"c1","from":"you","at":"2026-11-16T17:30:00Z","text":"Newer"}
     ],
     "decisions":[{"id":"d1","title":"Which key?","options":["A","B"],"from":"c1","at":"2026-11-16T17:40:00Z"}]}
    """#

    func report() throws -> AgentsReport { try AgentsReport.decode(Data(Self.json.utf8)) }

    @Test func groupsPutTheStuckFirst() throws {
        let groups = AgentsBoard.groups(try report())
        #expect(groups.map(\.name) == ["Example team", "Quiet team"])
        #expect(groups[0].agents.map(\.name) == ["builder.example", "conductor.example", "writer.example"])
        #expect(groups[0].waiting == 1)
        #expect(groups[1].working == 1)
    }

    @Test func conversationsAndMessagesReadByName() throws {
        let r = try report()
        let talks = AgentsBoard.conversations(r)
        #expect(talks.count == 1)
        #expect(talks[0].from == "conductor.example")
        #expect(talks[0].to == "builder.example")
        #expect(AgentsBoard.recent(r).map(\.id) == ["m2", "m1"])
        #expect(r.decisions?.first?.title == "Which key?")
        #expect(r.counts.working == 2)
        #expect(r.counts.waiting == 1)
    }

    @Test func timeInWords() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(AgentsBoard.since(nil, now: now) == "not known")
        #expect(AgentsBoard.since(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(AgentsBoard.since(now.addingTimeInterval(-600), now: now) == "10 min ago")
        #expect(AgentsBoard.since(now.addingTimeInterval(-7_200), now: now) == "2 h ago")
        #expect(AgentsBoard.since(now.addingTimeInterval(-3 * 86_400), now: now) == "3 days ago")
    }
}
