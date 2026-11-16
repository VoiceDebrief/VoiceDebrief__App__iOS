import Foundation
import Testing
@testable import CRM

/// Drafts, never sends: a template draft, and the log of one a person sent from the system's sheet.
struct DraftLogTests {
    var followUp: FollowUp {
        let stamp = Stamp(at: Invented.summit, by: Invented.me)
        return FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: Invented.source,
                        person: Invented.anaID, owner: "Owner", nextStep: "I will send you the deck on Friday", status: .open)
    }

    @Test func aTemplateDraftIsAValidRecord() {
        let d = DraftLog.draft(for: followUp, person: Invented.ana, channel: .email, by: .person("Owner"), at: Invented.later)
        #expect(d.to == [Invented.anaID])
        #expect(d.status == .draft)
        #expect(d.body.hasPrefix("Hello Ana,"))
        #expect(d.body.contains("I will send you the deck on Friday"))
        #expect(d.body.hasSuffix("Owner"))
        #expect(d.problems().isEmpty)
        #expect(DraftLog.recipients(d, people: [Invented.ana]) == ["ana@example.org"])
        let m = DraftLog.draft(for: followUp, person: Invented.ana, channel: .message, by: .person("Owner"), at: Invented.later)
        #expect(m.subject == nil)
        #expect(DraftLog.recipients(m, people: [Invented.ana]) == ["+44 20 7946 0000"])
    }

    @Test func sentByAPersonIsLoggedAsAnInteraction() throws {
        let me = Actor.person("Owner", key: "0011223344556677")
        let d = DraftLog.draft(for: followUp, person: Invented.ana, channel: .email, by: Invented.capture, at: Invented.later)
        let (done, interaction) = try DraftLog.sent(d, by: me, at: Invented.later)
        #expect(done.status == .sent)
        #expect(done.sentAs == interaction.id)
        #expect(done.changed.by == me)
        #expect(done.created.by == Invented.capture)
        #expect(done.problems().isEmpty)
        #expect(interaction.channel == .email)
        #expect(interaction.people == [Invented.anaID])
        #expect(interaction.draft == d.id)
        #expect(interaction.summary == "Sent: Good to meet you")
        #expect(interaction.problems().isEmpty)
        #expect(throws: DraftLog.Problem.alreadySent) { try DraftLog.sent(done, by: me, at: Invented.later) }
    }

    @Test func anAgentCannotMarkADraftSent() {
        let d = DraftLog.draft(for: followUp, person: Invented.ana, channel: .email, by: Invented.capture, at: Invented.later)
        #expect(throws: DraftLog.Problem.notAPerson) { try DraftLog.sent(d, by: Invented.capture, at: Invented.later) }
    }
}
