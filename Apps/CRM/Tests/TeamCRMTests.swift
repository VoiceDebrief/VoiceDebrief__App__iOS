import Foundation
import Testing
@testable import CRM

/// The team CRM's layout and crm-sources, as their owner described the structure (no values): every
/// value here is invented.
struct TeamCRMTests {
    let at = Invented.summit

    func json(_ text: String) -> Data { Data(text.utf8) }

    var teamFiles: [(path: String, data: Data)] {
        [
            ("companies/example-labs/company.json", json(#"{"id":"example-labs","type":"company","name":"Example Labs","state":"in conversation","sources":[],"updated_at":"2025-11-11T10:00:00Z","updated_by":"agent.example"}"#)),
            ("contacts/ana-exemplo/contact.json", json(#"{"id":"ana-exemplo","type":"contact","name":"Ana Exemplo","company":"example-labs","role":"CTO","email":"ana@example.org","linkedin":"https://example.org/in/ana","met":["Example Summit, day 2"],"owner":"Owner","pipeline":{"stage":"call booked","next":"Send the deck"},"updated_at":"2025-11-12T09:00:00Z","updated_by":"agent.example"}"#)),
            ("contacts/tom-sample/contact.json", json(#"{"id":"tom-sample","type":"contact","name":"Tom Sample","company":"Unlisted Example Co","updated_at":"2025-11-12T09:00:00Z","updated_by":"agent.example"}"#)),
            ("actions/2025-11-12-call-tom.json", json(#"{"id":"a1","type":"action","title":"Call Tom","kind":"follow-up","owner":"Owner","state":"open","due":"2025-11-20","contact":"tom-sample","updated_at":"2025-11-12T09:00:00Z","updated_by":"agent.example"}"#)),
            ("actions/2025-11-13-sealed.json", json(#"{"v":1,"id":"a2","kind":"follow-up","audience":["team"],"agents":[],"recipients":[{"to":"someone","key":"AAAA","env":{}}],"iv":"AAAA","ct":"AAAA","sealed_by":"x","at":"2025-11-13T09:00:00Z"}"#)),
            ("companies/example-labs/comms/t1/thread.json", json(#"{"id":"t1","type":"thread","subject":"Hello","owner":"Owner","state":"open"}"#)),
            ("schemas/contact.schema.json", json(#"{"type":"object"}"#)),
        ]
    }

    @Test func placesInTheLayout() {
        #expect(TeamCRMReader.place(of: "companies/x/company.json") == .company)
        #expect(TeamCRMReader.place(of: "contacts/x/contact.json") == .contact)
        #expect(TeamCRMReader.place(of: "actions/2025-11-12-x.json") == .action)
        #expect(TeamCRMReader.place(of: "companies/x/comms/t/thread.json") == .thread)
        #expect(TeamCRMReader.place(of: "people/x/contact.json") == nil)
        #expect(ImportScanner.kind(of: "schemas/contact.schema.json") == nil)
        #expect(ImportScanner.kind(of: "keys/jose-contacts.json") == nil)
        #expect(ImportScanner.kind(of: "jose-contacts.link.json") == nil)
    }

    @Test func contactsWithTheirCompanyStageAndNextStep() throws {
        let result = TeamCRMReader.read(teamFiles, file: "crm-private", at: at)
        #expect(result.candidates.map(\.name) == ["Ana Exemplo", "Tom Sample"])
        let ana = result.candidates[0]
        #expect(ana.organisation == "Example Labs")
        #expect(ana.role == "CTO")
        #expect(ana.emails == ["ana@example.org"])
        #expect(ana.links == ["https://example.org/in/ana"])
        #expect(ana.stage == "call booked")
        #expect(ana.nextStep == "Send the deck")
        #expect(ana.owner == "Owner")
        #expect(ana.notes.contains("Met: Example Summit, day 2"))
        #expect(ana.source.from == "crm-private/contacts/ana-exemplo/contact.json")
        #expect(ana.source.saidBy == "The team CRM, last changed by agent.example")
        let tom = result.candidates[1]
        #expect(tom.organisation == "Unlisted Example Co")
        #expect(tom.nextStep == "Call Tom")
        #expect(tom.due != nil)
        #expect(result.sealed == 1)
        #expect(result.companies == 1)
        #expect(result.skipped.contains { $0.path.hasSuffix("sealed.json") && $0.reason.contains("private key") })
        #expect(result.skipped.contains { $0.path.hasSuffix("thread.json") })
    }

    @Test func theScannerLeavesTheLayoutToItsReader() {
        let result = ImportScanner.scan(teamFiles, vault: "crm-private", at: at)
        #expect(result.candidates.count == 2)
        #expect(!result.skipped.contains { $0.path.hasPrefix("schemas/") })
    }

    @Test func aStageBecomesAStatusAndIsKept() {
        var c = ContactCandidate(name: "Ana Exemplo", emails: ["ana@example.org"], source: Invented.source)
        c.stage = "Won!"
        c.nextStep = "Send the contract"
        c.owner = "Someone"
        var proposals = ProposalMaker.make([c], people: [])
        proposals[0].decision = .accept
        let plan = ImportPlanner.plan(proposals, people: [], organisations: [],
                                      options: ImportOptions(followUp: "Batch step", owner: "Owner"), by: Invented.me, at: Invented.later)
        guard case .followUp(let f)? = plan.records.first(where: { $0.kind == .followUp }) else { Issue.record("no follow-up"); return }
        #expect(f.status == .done)
        #expect(f.stage == "Won!")
        #expect(f.nextStep == "Send the contract")
        #expect(f.owner == "Someone")
        #expect(PipelineStage.status(for: "parked") == .dropped)
        #expect(PipelineStage.status(for: "to follow up") == .open)
    }

    @Test func connectionsExportColumnsBecomeNotes() {
        let csv = "Name,Company,Job Title,Email,Industry,Location (Country),Connected At,Request Message\n"
            + "Ana Exemplo,Example Labs,CTO,ana@example.org,Fintech,Portugal,2025-11-12,\"Good to meet you, let's talk\"\n"
        let rows = TableReader.readCSV(csv, file: "jose-contacts/connections.csv", at: at)
        #expect(rows.count == 1)
        #expect(rows[0].role == "CTO")
        #expect(rows[0].notes == ["Industry: Fintech", "Location: Portugal", "Connected: 2025-11-12", "Their message: Good to meet you, let's talk"])
    }

    @Test func aVaultOfVaultsListsItsChildrenWithTheirKeys() {
        let files: [(path: String, data: Data)] = [
            ("index.json", json(#"{"about":"sources","vaults":[{"name":"one","label":"First","vault_id":"aaaa1111"},{"name":"two","label":"Second","vault_id":"bbbb2222"},{"name":"nokey","label":"No key","vault_id":"cccc3333"}]}"#)),
            ("keys/one.json", json(#"{"name":"one","label":"First","vault_id":"aaaa1111","endpoint":"https://dev.send.sgraph.ai","vault_key":"invented-key-text-one","purpose":"test"}"#)),
            ("keys/two.json", json(#"{"name":"two","label":"Second","vault_id":"bbbb2222","endpoint":"https://dev.send.sgraph.ai","vault_key":"invented-key-text-two","purpose":"test"}"#)),
            ("README.md", json("# Sources")),
        ]
        let children = VaultOfVaults.children(files)
        #expect(children.map(\.name) == ["one", "two"])
        #expect(children[0].label == "First")
        #expect(children[1].keyText == "invented-key-text-two")
        #expect(VaultOfVaults.children([("README.md", json("x"))]).isEmpty)
    }
}
