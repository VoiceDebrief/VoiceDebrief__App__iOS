import Foundation
import SGitVault
import Testing
@testable import CRM

/// The email workflow on the invented mailbox twin: verified correspondents become proposals with their
/// threads as interactions and a reply owed as a follow-up; the unverified sender is left out.
@MainActor
struct TwinReaderTests {
    let at = Date(timeIntervalSince1970: 1_794_823_200)

    @Test func correspondentsThreadsAndARepliesOwed() throws {
        let files = SampleData.twinFiles
        #expect(TwinReader.isTwin(files))
        let r = TwinReader.read(files, file: "mailbox", at: at)
        #expect(r.mailbox == "owner@example.org")
        #expect(r.candidates.map(\.name).sorted() == ["Ana Exemplo", "Rita Demo", "Tom Sample"])
        #expect(r.skipped.contains { $0.path == "prizes@example.net" && $0.reason.contains("DMARC") })
        #expect(!r.candidates.contains { $0.emails.contains("owner@example.org") })

        let ana = try #require(r.candidates.first { $0.name == "Ana Exemplo" })
        #expect(ana.nextStep == "Reply: Good to meet you at the summit")
        #expect(ana.due != nil)
        #expect(ana.events.count == 1)
        #expect(ana.events.first?.channel == .email)
        let tom = try #require(r.candidates.first { $0.name == "Tom Sample" })
        #expect(tom.nextStep == nil)   // you answered last
        let rita = try #require(r.candidates.first { $0.name == "Rita Demo" })
        #expect(rita.nextStep == nil)  // you wrote, she has not answered: waiting on her, not owed by you
        #expect(r.taken.contains("raw/messages/2026/11/m-1.json"))
    }

    @Test func aMailboxIsNotReadAsAnythingElse() {
        let result = ImportScanner.scan(SampleData.twinFiles, vault: "mailbox", at: at)
        #expect(result.candidates.count == 3)
        #expect(!result.skipped.contains { $0.path.hasPrefix("raw/") || $0.path.hasPrefix("threads/") })
    }

    @Test func acceptedThreadsBecomeInteractionsAndTheReplyAFollowUp() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crm-twin-\(UUID().uuidString)", directoryHint: .isDirectory)
        let crm = CRMVault(store: MemoryStore(), root: root, remote: FolderVaultTransport(root: root.appending(path: "unused")))
        try await crm.open()
        let session = ImportSession()
        session.addEvent = false
        session.addFollowUp = false
        await session.readSampleMailbox(into: crm)
        #expect(session.proposals.count == 3)
        session.decideAll(.accept)
        await session.keep(into: crm, name: "Owner")
        #expect(crm.people.count == 3)
        #expect(crm.interactions.filter { $0.channel == .email }.count == 3)
        #expect(crm.followUps.map(\.nextStep) == ["Reply: Good to meet you at the summit"])
    }
}
