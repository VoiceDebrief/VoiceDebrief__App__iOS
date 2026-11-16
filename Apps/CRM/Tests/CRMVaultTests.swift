import Foundation
import SGitVault
import Testing
@testable import CRM

/// The CRM vault on a device (a folder) and an import from another vault (a folder standing in for
/// the server), end to end: no network, invented people.
@MainActor
struct CRMVaultTests {
    func temporary(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "crm-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theVaultIsMadeOnceAndKeepsAnImport() async throws {
        let root = try temporary("device")
        let store = MemoryStore()
        let crm = CRMVault(store: store, root: root, remote: FolderVaultTransport(root: try temporary("unused")))
        try await crm.open()
        let id = try #require(crm.vaultID)
        #expect(crm.people.isEmpty)
        #expect(crm.commits == 1)

        var proposals = ProposalMaker.make([
            ContactCandidate(name: "Ana Exemplo", emails: ["ana@example.org"], organisation: "Example Labs",
                             source: Source(saidBy: "A vCard file", at: Invented.summit, from: "test.vcf, card 1")),
        ], people: crm.people)
        proposals[0].decision = .accept
        let plan = ImportPlanner.plan(proposals, people: crm.people, organisations: crm.organisations,
                                      options: ImportOptions(event: "Example Summit", followUp: "Say hello", owner: "Owner"),
                                      by: crm.actor(name: "Owner"), at: Date())
        let commit = try await crm.commit(plan, message: "Import: \(plan.summary)")
        #expect(!commit.isEmpty)
        #expect(crm.people.map(\.name.value) == ["Ana Exemplo"])
        #expect(crm.organisations.map(\.name.value) == ["Example Labs"])
        #expect(crm.followUps.count == 1)
        #expect(crm.interactions.count == 1)
        #expect(crm.commits == 2)
        #expect(crm.unreadable.isEmpty)
        #expect(crm.people[0].changed.by.key == crm.signerFingerprint)

        // Opened again (the app restarted): the same vault, the same records.
        let again = CRMVault(store: store, root: root, remote: FolderVaultTransport(root: try temporary("unused")))
        try await again.open()
        #expect(again.vaultID == id)
        #expect(again.people.map(\.id) == crm.people.map(\.id))
    }

    @Test func anImportReadsAnotherVaultByItsKey() async throws {
        // Another vault, with a vCard and a file the import ignores.
        let server = try temporary("server")
        let transport = FolderVaultTransport(root: server)
        let signer = SoftwareCommitSigner()
        let created = try await VaultCreate.create(signer: signer, accessToken: nil, writer: transport)
        let source = SGitVault(address: VaultAddress(vaultId: created.key.vaultId), readKey: created.key.readKey,
                               cache: try temporary("cache"), log: VaultTrafficLog(), transport: transport)
        _ = try await source.commit(["summit/contacts.vcf": Data("BEGIN:VCARD\nFN:Tom Sample\nEMAIL:tom@example.org\nEND:VCARD\n".utf8),
                                     "README.md": Data("# Contacts\n".utf8)],
                                    message: "Contacts", branch: "current", signer: signer,
                                    writeKey: try #require(created.key.writeKey), accessToken: nil, writer: transport)

        let crm = CRMVault(store: MemoryStore(), root: try temporary("device"), remote: transport)
        try await crm.open()
        let session = ImportSession()
        await session.read(keyText: created.keyText, into: crm)
        #expect(session.phase == .review)
        #expect(session.proposals.map(\.candidate.name) == ["Tom Sample"])
        #expect(session.proposals[0].candidate.source.from.hasSuffix("summit/contacts.vcf, card 1"))

        session.decideAll(.accept)
        await session.keep(into: crm, name: "Owner")
        guard case .kept(let message) = session.phase else { Issue.record("not kept: \(session.phase)"); return }
        #expect(message.hasPrefix("Kept 1 new person"))
        #expect(crm.people.map(\.name.value) == ["Tom Sample"])
        #expect(crm.followUps.first?.nextStep == "Follow up after Web Summit")
    }
}
