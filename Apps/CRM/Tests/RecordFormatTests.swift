import Foundation
import Testing
@testable import CRM

/// Invented people only: example.org addresses and Ofcom's drama telephone numbers.
enum Invented {
    static let summit = Date(timeIntervalSince1970: 1_762_855_200) // 11 November 2025, 10:00 UTC
    static let later = Date(timeIntervalSince1970: 1_763_287_200)
    static let me = Actor.person("Owner")
    static let capture = Actor.agent("crm.capture@sgit.example", key: "sha256:0f1e2d3c4b5a69788796a5b4c3d2e1f0")
    static let source = Source(saidBy: "Owner, in conversation", at: summit, from: "Example Summit, stand B12")
    static let badge = Source(saidBy: "Text read from a badge photo", at: summit, from: "photo IMG_0001.jpg")

    static let orgID = "6f0b8a52-3a1f-4c55-9e8e-2d7f0c1a9b01"
    static let anaID = "1d3e9a77-0c4b-4a3e-8f21-5b6c7d8e9f01"
    static let tomID = "2e4f0b88-1d5c-4b4f-9032-6c7d8e9f0a12"

    static var org: Organisation {
        Organisation(id: orgID, created: Stamp(at: summit, by: me), changed: Stamp(at: summit, by: me), source: source,
                     name: Sourced("Example Labs"), website: Sourced("https://example.org"))
    }

    static var ana: Person {
        Person(id: anaID, created: Stamp(at: summit, by: me), changed: Stamp(at: later, by: capture), source: source,
               name: Sourced("Ana Exemplo", source: badge),
               emails: [Sourced("ana@example.org")],
               phones: [Sourced("+44 20 7946 0000")],
               organisation: Sourced(orgID), role: Sourced("Head of Partnerships", source: badge),
               tags: ["example-summit"])
    }

    static var tom: Person {
        Person(id: tomID, created: Stamp(at: summit, by: me), changed: Stamp(at: summit, by: me), source: source,
               name: Sourced("Tom Sample"))
    }
}

struct RecordFormatTests {
    @Test func everyKindHasItsOwnFolder() {
        let folders = RecordKind.allCases.map(\.folder)
        #expect(folders == ["people", "organisations", "interactions", "introductions", "follow-ups", "drafts", "plays"])
        for kind in RecordKind.allCases { #expect(RecordKind(folder: kind.folder) == kind) }
    }

    @Test func aRecordIsOneFileInItsFolder() {
        #expect(Invented.ana.path == "people/\(Invented.anaID).json")
        #expect(Invented.org.path == "organisations/\(Invented.orgID).json")
        let parsed = RecordFiles.parse(path: "crm/people/\(Invented.anaID).json")
        #expect(parsed?.0 == .person)
        #expect(parsed?.1 == Invented.anaID)
        #expect(RecordFiles.parse(path: "people/not-an-id.json") == nil)
        #expect(RecordFiles.parse(path: "elsewhere/\(Invented.anaID).json") == nil)
    }

    @Test func aPersonReadsBackEqualAndTheSameBytes() throws {
        let data = try RecordFiles.encode(Invented.ana)
        let back = try RecordFiles.decode(path: Invented.ana.path, data: data)
        #expect(back == .person(Invented.ana))
        #expect(try RecordFiles.encode(Invented.ana) == data)
        #expect(data.last == 0x0A)
    }

    @Test func theFileIsSnakeCaseWithSources() throws {
        let intro = Introduction(id: "3f5a1c99-2e6d-4c50-a143-7d8e9f0a1b23",
                                 created: Stamp(at: Invented.summit, by: Invented.me),
                                 changed: Stamp(at: Invented.summit, by: Invented.me), source: Invented.source,
                                 suggestedBy: Sourced("A speaker on the panel"), between: [Invented.anaID, Invented.tomID],
                                 why: Sourced("Both are building on encrypted vaults"), status: .suggested)
        let json = try #require(JSONSerialization.jsonObject(with: RecordFiles.encode(intro)) as? [String: Any])
        #expect(json["suggested_by"] != nil)
        #expect(json["format"] as? String == "sgit.ai/crm/v1")
        let source = try #require(json["source"] as? [String: Any])
        #expect(source["said_by"] as? String == "Owner, in conversation")
        #expect(source["at"] as? String == "2025-11-11T10:00:00Z")
    }

    @Test func anAgentMustNameItsKey() {
        var person = Invented.tom
        person.changed = Stamp(at: Invented.later, by: Actor(kind: .agent, name: "crm.capture@sgit.example", key: nil))
        #expect(person.problems().contains { $0.contains("names no key") })
        #expect(throws: RecordFileError.self) { try RecordFiles.encode(person) }
        person.changed.by = Invented.capture
        #expect(person.problems().isEmpty)
    }

    @Test func anIntroductionIsBetweenTwoDifferentPeople() {
        var intro = Introduction(id: RecordID.make(), created: Stamp(at: Invented.summit, by: Invented.me),
                                 changed: Stamp(at: Invented.summit, by: Invented.me), source: Invented.source,
                                 suggestedBy: Sourced(Invented.tomID), between: [Invented.anaID, Invented.anaID],
                                 why: Sourced("They should talk"), status: .suggested)
        #expect(!intro.problems().isEmpty)
        intro.between = [Invented.anaID, Invented.tomID]
        #expect(intro.problems().isEmpty)
        intro.status = .made
        #expect(intro.problems().contains { $0.contains("names no interaction") })
    }

    @Test func onlyAPersonMarksADraftSent() {
        var draft = Draft(id: RecordID.make(), created: Stamp(at: Invented.summit, by: Invented.capture),
                          changed: Stamp(at: Invented.summit, by: Invented.capture), source: Invented.source,
                          to: [Invented.anaID], channel: .email, subject: "Good to meet you", body: "Hello Ana.", status: .draft)
        #expect(draft.problems().isEmpty)
        draft.status = .sent
        draft.sentAs = RecordID.make()
        #expect(draft.problems().contains { $0.contains("not a person") })
        draft.changed = Stamp(at: Invented.later, by: Invented.me)
        #expect(draft.problems().isEmpty)
    }

    @Test func aFollowUpWaitingNamesWhoItWaitsOn() {
        var follow = FollowUp(id: RecordID.make(), created: Stamp(at: Invented.summit, by: Invented.me),
                              changed: Stamp(at: Invented.summit, by: Invented.me), source: Invented.source,
                              person: Invented.anaID, owner: "Owner", nextStep: "Send the deck", due: Invented.later, status: .waiting)
        #expect(!follow.problems().isEmpty)
        follow.waitingOn = "Ana"
        #expect(follow.problems().isEmpty)
    }

    @Test func everyKindRoundTrips() throws {
        let stamp = Stamp(at: Invented.summit, by: Invented.me)
        let records: [AnyRecord] = [
            .person(Invented.ana),
            .organisation(Invented.org),
            .interaction(Interaction(id: RecordID.make(), created: stamp, changed: stamp, source: Invented.source,
                                     at: Invented.summit, channel: .meeting, people: [Invented.anaID], summary: "Met at the stand")),
            .followUp(FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: Invented.source,
                               person: Invented.anaID, owner: "Owner", nextStep: "Call", status: .open)),
            .play(Play(id: RecordID.make(), created: stamp, changed: stamp, source: Invented.source,
                       name: "After a conference", purpose: "Follow up everyone within a week",
                       steps: ["Import the contacts", "Review the proposals", "Draft the follow-ups"])),
        ]
        for record in records {
            let data: Data
            switch record {
            case .person(let r): data = try RecordFiles.encode(r)
            case .organisation(let r): data = try RecordFiles.encode(r)
            case .interaction(let r): data = try RecordFiles.encode(r)
            case .followUp(let r): data = try RecordFiles.encode(r)
            case .play(let r): data = try RecordFiles.encode(r)
            default: continue
            }
            #expect(try RecordFiles.decode(path: record.path, data: data) == record)
        }
    }

    @Test func aFileInTheWrongPlaceIsRefused() throws {
        let data = try RecordFiles.encode(Invented.ana)
        #expect(throws: RecordFileError.idMismatch(path: "people/\(Invented.tomID).json", id: Invented.anaID)) {
            try RecordFiles.decode(path: "people/\(Invented.tomID).json", data: data)
        }
        #expect(throws: (any Error).self) { try RecordFiles.decode(path: Invented.org.path, data: data) }
    }

    /// The example on website/crm/format/, as written there, reads as a valid person.
    @Test func theDocumentedExampleReads() throws {
        let text = """
        {
          "changed" : { "at" : "2025-11-12T09:30:00Z", "by" : { "key" : "sha256:0f1e2d3c4b5a69788796a5b4c3d2e1f0", "kind" : "agent", "name" : "crm.capture@sgit.example" } },
          "created" : { "at" : "2025-11-11T10:00:00Z", "by" : { "kind" : "person", "name" : "Owner" } },
          "emails" : [ { "value" : "ana@example.org" } ],
          "format" : "sgit.ai/crm/v1",
          "id" : "1d3e9a77-0c4b-4a3e-8f21-5b6c7d8e9f01",
          "links" : [ ],
          "name" : { "source" : { "at" : "2025-11-11T10:00:00Z", "from" : "photo IMG_0001.jpg", "said_by" : "Text read from a badge photo" }, "value" : "Ana Exemplo" },
          "notes" : [ ],
          "organisation" : { "value" : "6f0b8a52-3a1f-4c55-9e8e-2d7f0c1a9b01" },
          "phones" : [ { "value" : "+44 20 7946 0000" } ],
          "role" : { "value" : "Head of Partnerships" },
          "source" : { "at" : "2025-11-11T10:00:00Z", "from" : "Example Summit, stand B12", "said_by" : "Owner, in conversation" },
          "tags" : [ "example-summit" ]
        }
        """
        let record = try RecordFiles.decode(path: "people/1d3e9a77-0c4b-4a3e-8f21-5b6c7d8e9f01.json", data: Data(text.utf8))
        guard case .person(let ana) = record else { Issue.record("not a person"); return }
        #expect(ana.name.value == "Ana Exemplo")
        #expect(ana.changed.by.kind == .agent)
    }
}
