import Foundation
import Testing
@testable import VoiceDebrief

@Suite("The agents report")
struct AgentsReportTests {
    static let json = """
    {"v":1,"made":"2026-11-14T12:00:00Z","conductor":"claude-developer",
     "agents":[{"id":"claude-developer","name":"Claude (developer)","kind":"conductor","role":"Runs the app","status":"working","doing":"Agents screen"},
               {"id":"vaults","name":"Vaults","kind":"session","role":"Vaults","status":"waiting","doing":"Library on every device","waitingFor":"a green build","parent":"claude-developer"}],
     "links":[{"from":"claude-developer","to":"vaults","label":"lands its work"}],
     "messages":[{"id":"r1","agent":"claude-developer","from":"claude-developer","at":"2026-11-14T12:01:00Z","text":"Hello","replyTo":"m1"}]}
    """

    @Test func aReportReadsAndCounts() throws {
        let report = try AgentsReport.decode(Data(Self.json.utf8))
        #expect(report.agents.count == 2)
        #expect(report.counts.working == 1)
        #expect(report.counts.waiting == 1)
        #expect(report.messages.first?.replyTo == "m1")
    }
}
