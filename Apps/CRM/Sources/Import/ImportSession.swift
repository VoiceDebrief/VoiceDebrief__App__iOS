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
        case chooseSources
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
    /// When the vault opened lists other vaults (crm-sources), the ones it lists, and the ones chosen.
    private(set) var children: [VaultOfVaults.Child] = []
    var chosen: Set<String> = []

    var accepted: Int { proposals.filter { $0.decision == .accept }.count }
    var pending: Int { proposals.filter { $0.decision == .pending }.count }

    func reset() {
        phase = .start
        proposals = []
        skipped = []
        photosRead = 0
        children = []
        chosen = []
    }

    /// Reads a vault by its key and turns what it holds into proposals. A vault that lists other vaults
    /// (crm-sources) asks which of them to read first.
    func read(keyText: String, into crm: CRMVault) async {
        do {
            phase = .reading("Opening the vault")
            let (vault, files) = try await crm.importableFiles(keyText: keyText)
            sourceVault = vault
            let listed = VaultOfVaults.children(files)
            if !listed.isEmpty {
                children = listed
                chosen = Set(listed.map(\.name))
                phase = .chooseSources
                return
            }
            let result = await collect(files, label: "vault \(vault.prefix(8))")
            finish(result, looked: files.count, crm: crm)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The same as reading a vault, from invented sample files: to show the import before a real vault is to hand.
    func readSample(into crm: CRMVault) async {
        sourceVault = "sample"
        let result = await collect(SampleData.importFiles, label: "sample files")
        finish(result, looked: SampleData.importFiles.count, crm: crm)
    }

    /// Reads each chosen vault of a vault of vaults, one after another, into one set of proposals.
    func readChosen(into crm: CRMVault) async {
        var all = ImportScanner.Result()
        var looked = 0
        for child in children where chosen.contains(child.name) {
            do {
                phase = .reading("Opening \(child.label)")
                let (_, files) = try await crm.importableFiles(keyText: child.keyText)
                looked += files.count
                let result = await collect(files, label: child.name)
                all.candidates += result.candidates
                all.skipped += result.skipped.map { ImportScanner.Skipped(path: "\(child.name)/\($0.path)", reason: $0.reason) }
            } catch {
                all.skipped.append(ImportScanner.Skipped(path: child.name, reason: "could not be read: \(error.localizedDescription)"))
            }
        }
        finish(all, looked: looked, crm: crm)
    }

    /// The files of one vault as candidates, with the photos read on the device.
    private func collect(_ files: [(path: String, data: Data)], label: String) async -> ImportScanner.Result {
        let at = Date().toTheSecond
        phase = .reading("Reading \(files.count) \(files.count == 1 ? "file" : "files") in \(label)")
        var result = ImportScanner.scan(files, vault: label, at: at)
        let photos = files.filter { result.photos.contains($0.path) }
        for (n, photo) in photos.enumerated() {
            phase = .reading("Reading the text on photo \(n + 1) of \(photos.count) in \(label)")
            let lines = (try? await CardPhotoReader.lines(in: photo.data)) ?? []
            if let c = CardTextReader.read(lines: lines, file: "\(label)/\(photo.path)", at: at) {
                result.candidates.append(c)
                photosRead += 1
            } else {
                result.skipped.append(ImportScanner.Skipped(path: photo.path, reason: "no name, email or phone read on the photo"))
            }
        }
        return result
    }

    private func finish(_ result: ImportScanner.Result, looked: Int, crm: CRMVault) {
        skipped = result.skipped
        proposals = ProposalMaker.make(result.candidates, people: crm.people)
        phase = proposals.isEmpty ? .failed("Nothing read as a contact (\(looked) files looked at).") : .review
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
