import Foundation
import Testing
@testable import CRM

/// Who needs what, on invented follow-ups, with a fixed calendar and day.
struct FollowUpBoardTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_763_287_200) // 16 November 2025, 10:00 UTC

    func followUp(_ step: String, due: TimeInterval?, status: FollowUp.Status = .open, owner: String = "Owner", waitingOn: String? = nil) -> FollowUp {
        let stamp = Stamp(at: Invented.summit, by: Invented.me)
        return FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: Invented.source,
                        person: Invented.anaID, owner: owner, nextStep: step,
                        due: due.map { now.addingTimeInterval($0) }, status: status, waitingOn: waitingOn)
    }

    @Test func eachFollowUpLandsInItsBucket() {
        let day: TimeInterval = 86_400
        let cases: [(FollowUp, FollowUpBoard.Bucket)] = [
            (followUp("late", due: -2 * day), .overdue),
            (followUp("today", due: 3_600), .today),
            (followUp("soon", due: 3 * day), .thisWeek),
            (followUp("later", due: 30 * day), .later),
            (followUp("whenever", due: nil), .noDate),
            (followUp("their turn", due: -day, status: .waiting, waitingOn: "Ana"), .waiting),
            (followUp("finished", due: -day, status: .done), .closed),
            (followUp("parked", due: nil, status: .dropped), .closed),
        ]
        for (f, bucket) in cases {
            #expect(FollowUpBoard.bucket(f, now: now, calendar: calendar) == bucket, "\(f.nextStep)")
        }
    }

    @Test func theBoardNamesPeopleAndFiltersByOwner() {
        let list = [followUp("a", due: 86_400, owner: "Owner"), followUp("b", due: -86_400, owner: "Someone")]
        let all = FollowUpBoard.items(list, people: [Invented.ana], organisations: [Invented.org], owner: nil, now: now, calendar: calendar)
        #expect(all[.thisWeek]?.first?.personName == "Ana Exemplo")
        #expect(all[.thisWeek]?.first?.organisation == "Example Labs")
        #expect(all[.overdue]?.count == 1)
        let mine = FollowUpBoard.items(list, people: [Invented.ana], organisations: [], owner: "Owner", now: now, calendar: calendar)
        #expect(mine[.overdue] == nil)
        #expect(FollowUpBoard.owners(list) == ["Owner", "Someone"])
    }

    @Test func aChangeIsStampedByThePersonAndChecked() {
        let f = followUp("Send the deck", due: nil)
        let me = Actor.person("Owner", key: "0011223344556677")
        let waiting = FollowUpBoard.changed(f, status: .waiting, nextStep: " Wait for the reply ", due: nil, waitingOn: "Ana", by: me, at: now)
        #expect(waiting.status == .waiting)
        #expect(waiting.nextStep == "Wait for the reply")
        #expect(waiting.waitingOn == "Ana")
        #expect(waiting.changed.by == me)
        #expect(waiting.created == f.created)
        #expect(waiting.problems().isEmpty)
        let done = FollowUpBoard.changed(waiting, status: .done, nextStep: "Sent", due: nil, waitingOn: "Ana", by: me, at: now)
        #expect(done.waitingOn == nil)
        let bad = FollowUpBoard.changed(f, status: .waiting, nextStep: "x", due: nil, waitingOn: "", by: me, at: now)
        #expect(!bad.problems().isEmpty)
    }
}
