import Foundation
import Observation

/// One import, from a vault's key to a signed commit: read the files, read the photos, propose, let a
/// person decide, keep what was accepted.
@MainActor
@Observable
final class ImportSession {
    enum Phase: Equatable {
        case start
        case reading(String)
        case review
        case kept(String)
        case failed(String)
    }

    private(set) var phase: Phase = .start
    var proposals: [Proposal] = []
    private(set) var sourceVault = ""
    private(set) var skipped: [ImportScanner.Skipped] = []
    private(set) var photosRead = 0
    var options = ImportOptions(event: "Web Summit 2026", followUp: "Follow up after Web Summit", owner: "")
    var addEvent = true
    var addFollowUp = true

    var accepted: Int { proposals.filter { $0.decision == .accept }.count }
    var pending: Int { proposals.filter { $0.decision == .pending }.count }

    func reset() {
        phase = .start
        proposals = []
        skipped = []
        photosRead = 0
    }

    /// Reads a vault by its key and turns what it holds into proposals.
    func read(keyText: String, into crm: CRMVault) async {
        let at = Date().toTheSecond
        do {
            phase = .reading("Opening the vault")
            let (vault, files) = try await crm.importableFiles(keyText: keyText)
            sourceVault = vault
            phase = .reading("Reading \(files.count) \(files.count == 1 ? "file" : "files")")
            var result = ImportScanner.scan(files, vault: "vault \(vault.prefix(8))", at: at)
            let photos = files.filter { result.photos.contains($0.path) }
            for (n, photo) in photos.enumerated() {
                phase = .reading("Reading the text on photo \(n + 1) of \(photos.count)")
                let lines = (try? await CardPhotoReader.lines(in: photo.data)) ?? []
                if let c = CardTextReader.read(lines: lines, file: "vault \(vault.prefix(8))/\(photo.path)", at: at) {
                    result.candidates.append(c)
                    photosRead += 1
                } else {
                    result.skipped.append(ImportScanner.Skipped(path: photo.path, reason: "no name, email or phone read on the photo"))
                }
            }
            skipped = result.skipped
            proposals = ProposalMaker.make(result.candidates, people: crm.people)
            phase = proposals.isEmpty ? .failed("Nothing in that vault reads as a contact (\(files.count) files looked at).") : .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func decideAll(_ decision: Proposal.Decision) {
        for i in proposals.indices where proposals[i].decision == .pending || decision == .pending {
            proposals[i].decision = decision
        }
    }

    func set(_ id: String, _ decision: Proposal.Decision) {
        if let i = proposals.firstIndex(where: { $0.id == id }) { proposals[i].decision = decision }
    }

    /// The accepted proposals, written to the CRM vault as one signed commit.
    func keep(into crm: CRMVault, name: String) async {
        var opts = options
        opts.owner = name.isEmpty ? "Me" : name
        if !addEvent { opts.event = nil }
        if !addFollowUp { opts.followUp = nil }
        let plan = ImportPlanner.plan(proposals, people: crm.people, organisations: crm.organisations,
                                      options: opts, by: crm.actor(name: name), at: Date())
        guard !plan.records.isEmpty else { phase = .failed("Nothing was accepted, so nothing was kept."); return }
        do {
            phase = .reading("Keeping \(plan.summary)")
            let commit = try await crm.commit(plan, message: "Import from vault \(sourceVault.prefix(8)): \(plan.summary)")
            phase = .kept("Kept \(plan.summary), in one signed commit (\(commit.prefix(8))).")
            proposals = []
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
