import Foundation
import SGitVault
import Testing
@testable import CRM

/// The sample data is valid, invented, joined up, and makes a board worth showing.
@MainActor
struct SampleDataTests {
    let records = SampleData.records(now: Date(timeIntervalSince1970: 1_794_823_200), by: .person("Owner"))

    @Test func everyRecordIsValid() throws {
        for r in records { #expect(r.record.problems().isEmpty, "\(r.path): \(r.record.problems())") }
        _ = try RecordFiles.files(records)
    }

    @Test func everyPersonIsInvented() {
        for case .person(let p) in records {
            for e in p.emails { #expect(e.value.hasSuffix("@example.org") || e.value.hasSuffix("@example.com")) }
            for t in p.phones { #expect(t.value.hasPrefix("+44 20 7946 0")) }
        }
        for (_, data) in SampleData.importFiles {
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("@gmail") && !text.contains("@sgit.ai"))
        }
    }

    @Test func everyReferenceResolves() {
        let people = Set(records.compactMap { if case .person(let p) = $0 { return p.id } else { return nil } })
        let orgs = Set(records.compactMap { if case .organisation(let o) = $0 { return o.id } else { return nil } })
        let interactions = Set(records.compactMap { if case .interaction(let i) = $0 { return i.id } else { return nil } })
        for r in records {
            switch r {
            case .person(let p): if let o = p.organisation?.value { #expect(orgs.contains(o)) }
            case .followUp(let f): #expect(people.contains(f.person))
            case .interaction(let i): #expect(Set(i.people).isSubset(of: people))
            case .introduction(let n):
                #expect(Set(n.between).isSubset(of: people))
                if let m = n.madeIn { #expect(interactions.contains(m)) }
            case .draft(let d): #expect(Set(d.to).isSubset(of: people))
            default: break
            }
        }
        #expect(records.filter { $0.kind == .introduction }.count == 2)
    }

    @Test func theBoardHasSomethingInEachKindOfBucket() {
        let followUps = records.compactMap { if case .followUp(let f) = $0 { return f } else { return nil } }
        let now = Date(timeIntervalSince1970: 1_794_823_200)
        let board = FollowUpBoard.items(followUps, people: [], organisations: [], owner: nil, now: now)
        for bucket in [FollowUpBoard.Bucket.overdue, .today, .thisWeek, .later, .noDate, .waiting, .closed] {
            #expect(board[bucket]?.isEmpty == false, "\(bucket)")
        }
    }

    @Test func seedingFillsOnlyAnEmptyVault() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crm-sample-\(UUID().uuidString)", directoryHint: .isDirectory)
        let crm = CRMVault(store: MemoryStore(), root: root, remote: FolderVaultTransport(root: root.appending(path: "unused")))
        try await crm.open()
        try await crm.seedSampleIfEmpty(name: "Owner")
        #expect(crm.people.count == SampleData.seeds.count)
        #expect(crm.introductions.count == 2)
        #expect(crm.drafts.count == 1)
        #expect(crm.commits == 2)
        try await crm.seedSampleIfEmpty(name: "Owner")
        #expect(crm.commits == 2)
    }

    @Test func theSampleFilesImportAsProposals() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crm-sample-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        let crm = CRMVault(store: MemoryStore(), root: root, remote: FolderVaultTransport(root: root.appending(path: "unused")))
        try await crm.open()
        let session = ImportSession()
        await session.readSample(into: crm)
        #expect(session.phase == .review)
        // Nora is in the vCard and the CSV: one proposal. Ana, Sam and Kai make four.
        #expect(session.proposals.map(\.candidate.name).sorted() == ["Ana Exemplo", "Kai Sample", "Nora Example", "Sam Imaginary"])
    }
}
