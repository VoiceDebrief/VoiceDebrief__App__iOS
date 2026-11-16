import Foundation
import Testing
@testable import CRM

/// The import readers on invented files: example.org addresses, Ofcom drama numbers (+44 20 7946 0xxx).
struct ImportReaderTests {
    let at = Invented.summit

    @Test func aVCardWithFoldingGroupsAndEscapes() {
        let vcf = """
        BEGIN:VCARD\r
        VERSION:3.0\r
        N:Exemplo;Ana;;;\r
        FN:Ana Exemplo\r
        ORG:Example Labs;Partnerships\r
        TITLE:Head of Partnerships\r
        item1.EMAIL;type=INTERNET;type=WORK:ana@example.org\r
        TEL;type=CELL:+44 20 7946 0001\r
        NOTE:Met at the stand\\, wants the deck\\nCall in December\r
        URL:https://example.org/\r
         ana\r
        END:VCARD\r
        BEGIN:VCARD\r
        VERSION:4.0\r
        N:Sample;Tom;;;\r
        EMAIL:tom@example.org\r
        END:VCARD\r
        """
        let cards = VCardReader.read(vcf, file: "vault/contacts.vcf", at: at)
        #expect(cards.count == 2)
        let ana = cards[0]
        #expect(ana.name == "Ana Exemplo")
        #expect(ana.emails == ["ana@example.org"])
        #expect(ana.phones == ["+44 20 7946 0001"])
        #expect(ana.organisation == "Example Labs, Partnerships")
        #expect(ana.role == "Head of Partnerships")
        #expect(ana.notes == ["Met at the stand, wants the deck\nCall in December"])
        #expect(ana.links == ["https://example.org/ana"])
        #expect(ana.source.from == "vault/contacts.vcf, card 1")
        #expect(cards[1].name == "Tom Sample")
    }

    @Test func aCSVWithQuotesAndLooseHeadings() {
        let csv = "First Name,Last Name,E-mail Address,Company,Job Title,Notes\r\n"
            + "Ana,Exemplo,ana@example.org,\"Example Labs, Lisbon\",CTO,\"Said \"\"yes\"\" to a demo\"\r\n"
            + ",,tom.sample@example.org,,,\r\n"
            + "\r\n"
        let rows = TableReader.readCSV(csv, file: "v/leads.csv", at: at)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Ana Exemplo")
        #expect(rows[0].organisation == "Example Labs, Lisbon")
        #expect(rows[0].role == "CTO")
        #expect(rows[0].notes == ["Said \"yes\" to a demo"])
        #expect(rows[0].source.from == "v/leads.csv, row 2")
        #expect(rows[1].name == "Tom Sample")
    }

    @Test func aSemicolonCSVAndOneWithNoPeople() {
        let csv = "Name;Email\nAna Exemplo;ana@example.org\n"
        #expect(TableReader.readCSV(csv, file: "f", at: at).first?.emails == ["ana@example.org"])
        #expect(TableReader.readCSV("date,amount\n2025-11-11,12\n", file: "f", at: at).isEmpty)
    }

    @Test func aJSONListUnderAKey() {
        let json = #"{"attendees":[{"name":"Ana Exemplo","email":"ana@example.org","company":"Example Labs","linkedin":"https://example.org/in/ana"},{"title":"No name or contact"}]}"#
        let found = TableReader.readJSON(Data(json.utf8), file: "v/a.json", at: at)
        #expect(found.count == 1)
        #expect(found[0].links == ["https://example.org/in/ana"])
        #expect(found[0].organisation == "Example Labs")
    }

    @Test func theTextOfABusinessCard() throws {
        let lines = ["EXAMPLE LABS LTD", "Ana Exemplo", "Head of Partnerships", "ana@example.org", "M: +44 20 7946 0001", "www.example.org", "Lisbon"]
        let c = try #require(CardTextReader.read(lines: lines, file: "v/IMG_0001.jpg", at: at))
        #expect(c.name == "Ana Exemplo")
        #expect(c.organisation == "EXAMPLE LABS LTD")
        #expect(c.role == "Head of Partnerships")
        #expect(c.emails == ["ana@example.org"])
        #expect(c.phones == ["+44 20 7946 0001"])
        #expect(c.links == ["www.example.org"])
        #expect(c.notes == ["Also on the card: Lisbon"])
        #expect(c.source.saidBy.contains("photo"))
    }

    @Test func theScannerSendsEachFileToItsReader() throws {
        let person = try RecordFiles.encode(Invented.ana)
        let files: [(path: String, data: Data)] = [
            (Invented.ana.path, person),
            ("cards/one.vcf", Data("BEGIN:VCARD\nFN:Tom Sample\nEMAIL:tom@example.org\nEND:VCARD\n".utf8)),
            ("photos/badge.HEIC", Data()),
            ("notes/readme.md", Data("hello".utf8)),
            ("sheets/costs.csv", Data("date,amount\n1,2\n".utf8)),
        ]
        let result = ImportScanner.scan(files, vault: "summit", at: at)
        #expect(result.candidates.map(\.name) == ["Ana Exemplo", "Tom Sample"])
        #expect(result.photos == ["photos/badge.HEIC"])
        #expect(result.skipped.map(\.path) == ["sheets/costs.csv"])
    }
}

struct ProposalTests {
    let at = Invented.summit

    func candidate(_ name: String, email: String? = nil, phone: String? = nil, org: String? = nil, from: String = "f") -> ContactCandidate {
        ContactCandidate(name: name, emails: email.map { [$0] } ?? [], phones: phone.map { [$0] } ?? [], organisation: org,
                         source: Source(saidBy: "A test file", at: at, from: from))
    }

    @Test func theSamePersonTwiceInAnImportIsOneProposal() {
        let list = [candidate("Ana", email: "ANA@example.org", from: "a.vcf"),
                    candidate("Ana Exemplo", email: "ana@example.org", phone: "+44 20 7946 0001", from: "b.csv"),
                    candidate("A. Exemplo", phone: "020 7946 0001")]
        let proposals = ProposalMaker.make(list, people: [])
        #expect(proposals.count == 1)
        #expect(proposals[0].candidate.name == "Ana Exemplo")
        #expect(proposals[0].candidate.source.note == "also in b.csv; also in f")
    }

    @Test func aProposalNamesThePersonItMatches() {
        let same = ProposalMaker.make([candidate("A. Exemplo", email: "ana@example.org")], people: [Invented.ana])
        #expect(same[0].match?.personID == Invented.anaID)
        #expect(same[0].match?.strength == .same)
        let byName = ProposalMaker.make([candidate("tom  SAMPLE")], people: [Invented.tom])
        #expect(byName[0].match?.strength == .likely)
        #expect(ProposalMaker.make([candidate("Someone Else")], people: [Invented.ana, Invented.tom])[0].match == nil)
    }

    @Test func onlyAcceptedProposalsBecomeRecords() throws {
        var proposals = ProposalMaker.make([candidate("Lee Example", email: "lee@example.org", org: "Example Labs"),
                                            candidate("Kim Example", email: "kim@example.org", org: "Other Example Co"),
                                            candidate("Ana Exemplo", email: "ana@example.org", phone: "+44 20 7946 0999")],
                                           people: [Invented.ana])
        proposals[0].decision = .accept
        proposals[1].decision = .drop
        proposals[2].decision = .accept
        let options = ImportOptions(event: "Example Summit", followUp: "Follow up after the summit", owner: "Owner")
        let plan = ImportPlanner.plan(proposals, people: [Invented.ana], organisations: [Invented.org],
                                      options: options, by: Invented.me, at: Invented.later)
        #expect(plan.newPeople == 1)
        #expect(plan.updatedPeople == 1)
        #expect(plan.newOrganisations == 0)
        let files = try plan.files()
        #expect(files.keys.filter { $0.hasPrefix("people/") }.count == 2)
        #expect(files.keys.filter { $0.hasPrefix("interactions/") }.count == 1)
        #expect(files.keys.filter { $0.hasPrefix("follow-ups/") }.count == 1)
        #expect(!files.keys.contains { $0.hasPrefix("organisations/") })

        // The match gained the new phone, with the import as its source, and kept what it had.
        guard case .person(let ana)? = plan.records.first(where: { $0.id == Invented.anaID }) else { Issue.record("no update"); return }
        #expect(ana.phones.map(\.value) == ["+44 20 7946 0000", "+44 20 7946 0999"])
        #expect(ana.phones[1].source?.saidBy == "A test file")
        #expect(ana.emails.count == 1)
        #expect(ana.created == Invented.ana.created)
        #expect(ana.changed.by == Invented.me)

        // The new person belongs to the organisation already there.
        guard case .person(let lee)? = plan.records.first(where: {
            if case .person(let p) = $0 { return p.name.value == "Lee Example" } else { return false }
        }) else { Issue.record("no new person"); return }
        #expect(lee.organisation?.value == Invented.orgID)
        #expect(plan.summary == "1 new person, 1 updated")
    }

    @Test func aNewOrganisationIsMadeOnceForABatch() {
        var proposals = ProposalMaker.make([candidate("Lee Example", email: "lee@example.org", org: "New Example Co"),
                                            candidate("Kim Example", email: "kim@example.org", org: "new example co")], people: [])
        for i in proposals.indices { proposals[i].decision = .accept }
        let plan = ImportPlanner.plan(proposals, people: [], organisations: [],
                                      options: ImportOptions(owner: "Owner"), by: Invented.me, at: Invented.later)
        #expect(plan.newOrganisations == 1)
        #expect(plan.newPeople == 2)
        #expect(plan.records.count == 3)
    }
}
