import SwiftUI
import UIKit

/// Import from a vault: its key (typed, pasted or scanned), then each contact found as a proposal to
/// accept, change or drop, then one signed commit of what was accepted.
struct ImportView: View {
    let crm: CRMVault
    @State private var session = ImportSession()
    @State private var keyText = ""
    @State private var scanning = false
    @State private var editing: Proposal?
    @AppStorage("crm.myName") private var myName = ""

    var body: some View {
        List {
            switch session.phase {
            case .start:
                startSection
            case .reading(let what):
                Section { HStack { ProgressView(); Text(what) } }
            case .chooseSources:
                Section {
                    ForEach(session.children) { child in
                        Toggle(isOn: Binding(get: { session.chosen.contains(child.name) },
                                             set: { on in if on { session.chosen.insert(child.name) } else { session.chosen.remove(child.name) } })) {
                            VStack(alignment: .leading) {
                                Text(child.label)
                                Text(child.vaultID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("This vault lists \(session.children.count) vaults")
                } footer: {
                    Text("Each is read with the key this vault holds for it, for this import only. Files sealed to the team's keys cannot be read yet and are listed after.")
                }
                Section {
                    Button("Read \(session.chosen.count) \(session.chosen.count == 1 ? "vault" : "vaults")") {
                        Task { await session.readChosen(into: crm) }
                    }
                    .disabled(session.chosen.isEmpty)
                    Button("Start again", role: .cancel) { session.reset() }
                }
            case .review:
                reviewSections
            case .kept(let message):
                Section {
                    Label(message, systemImage: "checkmark.seal")
                    Button("Import from another vault") { session.reset(); keyText = "" }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                    Button("Start again") { session.reset() }
                }
            }
        }
        .navigationTitle("Import")
        .sheet(isPresented: $scanning) {
            QRScanner { text in
                keyText = text
                scanning = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editing) { proposal in
            NavigationStack {
                ProposalEditor(proposal: proposal, existing: crm.people.first { $0.id == proposal.match?.personID }) { changed in
                    if let i = session.proposals.firstIndex(where: { $0.id == changed.id }) { session.proposals[i] = changed }
                    editing = nil
                }
            }
        }
    }

    private var startSection: some View {
        Group {
            Section {
                TextField("Vault key or read key", text: $keyText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                HStack {
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string { keyText = text }
                    }
                    if QRScanner.canScan {
                        Spacer()
                        Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("The vault to import from")
            } footer: {
                Text("The app reads vCards, CSV files, JSON lists, records in the SGit CRM format, and the text on photos of business cards and badges (read on this device). Nothing is kept until you accept it.")
            }
            Section {
                Button("Read the vault") {
                    Task { await session.read(keyText: keyText, into: crm) }
                }
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || crm.vaultID == nil)
            }
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section {
            Text("\(session.proposals.count) found, \(session.accepted) accepted, \(session.pending) to decide")
            HStack {
                Button("Accept all") { session.decideAll(.accept) }
                Spacer()
                Button("Drop all") { session.decideAll(.drop) }
                Spacer()
                Button("Undecide") { session.decideAll(.pending) }
            }
            .buttonStyle(.borderless)
        } footer: {
            if session.photosRead > 0 { Text("\(session.photosRead) read from photos: check those names.") }
        }

        Section("Proposals") {
            ForEach(session.proposals) { proposal in
                ProposalRow(proposal: proposal) { decision in
                    session.set(proposal.id, decision)
                } edit: {
                    editing = proposal
                }
            }
        }

        Section {
            TextField("Your name", text: $myName)
            Toggle("Note where you met", isOn: $session.addEvent)
            if session.addEvent {
                TextField("Where", text: Binding(get: { session.options.event ?? "" }, set: { session.options.event = $0 }))
            }
            Toggle("Add a follow-up for each new person", isOn: $session.addFollowUp)
            if session.addFollowUp {
                TextField("Next step", text: Binding(get: { session.options.followUp ?? "" }, set: { session.options.followUp = $0 }))
            }
        } header: {
            Text("With each new person")
        }

        if !session.skipped.isEmpty {
            Section("Looked at, nothing found") {
                ForEach(session.skipped, id: \.path) { item in
                    VStack(alignment: .leading) {
                        Text(item.path).font(.footnote.monospaced())
                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            Button("Keep \(session.accepted) accepted") {
                Task { await session.keep(into: crm, name: myName) }
            }
            .disabled(session.accepted == 0)
        } footer: {
            Text("One signed commit to your CRM vault on this device.")
        }
    }
}

struct ProposalRow: View {
    let proposal: Proposal
    let decide: (Proposal.Decision) -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(proposal.candidate.name).font(.headline)
                    if let line = [proposal.candidate.role, proposal.candidate.organisation].compactMap({ $0 }).joined(separator: ", ").nonEmpty {
                        Text(line).font(.subheadline)
                    }
                    if let contact = (proposal.candidate.emails + proposal.candidate.phones).first {
                        Text(contact).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Change", systemImage: "pencil", action: edit).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if let match = proposal.match {
                Label("Adds to \(match.name): \(match.reasons.joined(separator: ", "))",
                      systemImage: match.strength == .same ? "link" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(match.strength == .same ? Color.accentColor : .orange)
            }
            Text(proposal.candidate.source.from).font(.caption2).foregroundStyle(.secondary)
            Picker("Decision", selection: Binding(get: { proposal.decision }, set: decide)) {
                Text("Decide").tag(Proposal.Decision.pending)
                Text("Accept").tag(Proposal.Decision.accept)
                Text("Drop").tag(Proposal.Decision.drop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// A proposal beside the record it would add to: change its values, or stop it matching.
struct ProposalEditor: View {
    @State var proposal: Proposal
    let existing: Person?
    let done: (Proposal) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Form {
            if let existing, sizeClass == .regular {
                Section {
                    HStack(alignment: .top, spacing: 24) {
                        column("Proposed", fields)
                        column("In your CRM", AnyView(PersonSummary(person: existing)))
                    }
                }
            } else {
                Section("Proposed") { fields }
                if let existing {
                    Section("In your CRM") { PersonSummary(person: existing) }
                }
            }
            if proposal.match != nil {
                Section {
                    Button("Not the same person: make a new one") { proposal.match = nil }
                }
            }
            Section("Where it came from") {
                Text(proposal.candidate.source.saidBy)
                Text(proposal.candidate.source.from).font(.footnote.monospaced())
                if let note = proposal.candidate.source.note { Text(note).font(.footnote) }
            }
        }
        .navigationTitle(proposal.candidate.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Accept") { proposal.decision = .accept; done(proposal) }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { done(proposal) }
            }
        }
    }

    private func column(_ title: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: AnyView {
        AnyView(VStack(alignment: .leading) {
            TextField("Name", text: $proposal.candidate.name)
            TextField("Organisation", text: Binding(get: { proposal.candidate.organisation ?? "" },
                                                   set: { proposal.candidate.organisation = $0.isEmpty ? nil : $0 }))
            TextField("Role", text: Binding(get: { proposal.candidate.role ?? "" },
                                           set: { proposal.candidate.role = $0.isEmpty ? nil : $0 }))
            TextField("Emails, separated by commas", text: Binding(get: { proposal.candidate.emails.joined(separator: ", ") },
                                                                    set: { proposal.candidate.emails = split($0) }))
                .textInputAutocapitalization(.never)
            TextField("Phones, separated by commas", text: Binding(get: { proposal.candidate.phones.joined(separator: ", ") },
                                                                    set: { proposal.candidate.phones = split($0) }))
        })
    }

    private func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
