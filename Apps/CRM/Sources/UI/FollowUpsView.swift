import SwiftUI

/// Who needs what (W3): every follow-up by bucket, for one owner or everyone. Changing one is a signed commit.
struct FollowUpsView: View {
    let crm: CRMVault
    var trySample: (() -> Void)?
    @State private var owner: String?
    @State private var editing: FollowUp?
    @State private var problem: String?
    @AppStorage("crm.myName") private var myName = ""

    var body: some View {
        let board = FollowUpBoard.items(crm.followUps, people: crm.people, organisations: crm.organisations, owner: owner, now: Date())
        List {
            if crm.followUps.isEmpty {
                ContentUnavailableView {
                    Label("Nobody to follow up yet", systemImage: "checklist")
                } description: {
                    Text("Import contacts with a follow-up each, and they appear here by date.")
                } actions: {
                    if let trySample { Button("Try with sample data", action: trySample) }
                }
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote) }
            ForEach(FollowUpBoard.Bucket.allCases) { bucket in
                if let items = board[bucket], !items.isEmpty {
                    Section("\(bucket.title) · \(items.count)") {
                        ForEach(items) { item in
                            Button { editing = item.followUp } label: { FollowUpRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Follow-ups")
        .toolbar {
            if !crm.followUps.isEmpty {
                Menu {
                    Picker("Owner", selection: $owner) {
                        Text("Everyone").tag(String?.none)
                        ForEach(FollowUpBoard.owners(crm.followUps), id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Label(owner ?? "Everyone", systemImage: "person.crop.circle")
                }
            }
        }
        .sheet(item: $editing) { f in
            NavigationStack {
                FollowUpEditor(followUp: f, personName: crm.people.first { $0.id == f.person }?.name.value ?? "") { changed in
                    editing = nil
                    Task {
                        do {
                            try await crm.commit(records: [.followUp(changed)], message: "Follow-up: \(changed.status.rawValue), \(changed.nextStep)")
                            problem = nil
                        } catch { problem = error.localizedDescription }
                    }
                } actorName: { myName } actor: { crm.actor(name: myName) } draftIt: { channel in
                    editing = nil
                    guard let person = crm.people.first(where: { $0.id == f.person }) else { problem = "This follow-up's person is not in the CRM."; return }
                    let draft = DraftLog.draft(for: f, person: person, channel: channel, by: crm.actor(name: myName), at: Date())
                    Task {
                        do { try await crm.commit(records: [.draft(draft)], message: "Draft for \(person.name.value)"); problem = nil }
                        catch { problem = error.localizedDescription }
                    }
                }
            }
        }
    }
}

struct FollowUpRow: View {
    let item: FollowUpBoard.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.personName).font(.headline)
                Spacer()
                if let due = item.followUp.due {
                    Text(due, format: .dateTime.day().month(.abbreviated))
                        .font(.caption).foregroundStyle(item.bucket == .overdue ? .red : .secondary)
                }
            }
            Text(item.followUp.nextStep)
            HStack(spacing: 6) {
                if let org = item.organisation { Text(org) }
                Text("· \(item.followUp.owner)")
                if let stage = item.followUp.stage { Text("· \(stage)") }
                if let who = item.followUp.waitingOn { Text("· waiting on \(who)") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct FollowUpEditor: View {
    let followUp: FollowUp
    let personName: String
    let save: (FollowUp) -> Void
    let actorName: () -> String
    let actor: () -> Actor
    var draftIt: ((Draft.Channel) -> Void)?
    @State private var status: FollowUp.Status
    @State private var nextStep: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var waitingOn: String
    @Environment(\.dismiss) private var dismiss

    init(followUp: FollowUp, personName: String, save: @escaping (FollowUp) -> Void,
         actorName: @escaping () -> String, actor: @escaping () -> Actor, draftIt: ((Draft.Channel) -> Void)? = nil) {
        self.draftIt = draftIt
        self.followUp = followUp
        self.personName = personName
        self.save = save
        self.actorName = actorName
        self.actor = actor
        _status = State(initialValue: followUp.status)
        _nextStep = State(initialValue: followUp.nextStep)
        _hasDue = State(initialValue: followUp.due != nil)
        _due = State(initialValue: followUp.due ?? Date())
        _waitingOn = State(initialValue: followUp.waitingOn ?? "")
    }

    private var changed: FollowUp {
        FollowUpBoard.changed(followUp, status: status, nextStep: nextStep, due: hasDue ? due : nil,
                              waitingOn: waitingOn, by: actor(), at: Date())
    }

    var body: some View {
        Form {
            Section {
                Picker("Status", selection: $status) {
                    Text("Open").tag(FollowUp.Status.open)
                    Text("Waiting").tag(FollowUp.Status.waiting)
                    Text("Done").tag(FollowUp.Status.done)
                    Text("Dropped").tag(FollowUp.Status.dropped)
                }
                .pickerStyle(.segmented)
                TextField("Next step", text: $nextStep, axis: .vertical)
                Toggle("A date", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                if status == .waiting { TextField("Waiting on", text: $waitingOn) }
            }
            if let draftIt {
                Section {
                    Button("Draft an email") { draftIt(.email) }
                    Button("Draft a message") { draftIt(.message) }
                } footer: {
                    Text("A draft to read and change. You send it yourself.")
                }
            }
            Section("Where it came from") {
                Text("\(followUp.source.saidBy), \(followUp.source.from)").font(.footnote)
                if let stage = followUp.stage { LabeledContent("Stage, as written", value: stage) }
                LabeledContent("Owner", value: followUp.owner)
            }
            let problems = changed.problems()
            if !problems.isEmpty {
                Section { ForEach(problems, id: \.self) { Text($0).foregroundStyle(.red) } }
            }
        }
        .navigationTitle(personName.isEmpty ? "Follow-up" : personName)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Keep") { save(changed) }.disabled(!changed.problems().isEmpty)
            }
        }
    }
}

/// Introductions to make or made: who suggested it, between whom, why, and whether it happened.
struct IntroductionsView: View {
    let crm: CRMVault

    private func name(_ id: String) -> String { crm.people.first { $0.id == id }?.name.value ?? id }

    var body: some View {
        Group {
            if crm.introductions.isEmpty {
                ContentUnavailableView("No introductions yet", systemImage: "arrow.left.arrow.right",
                                       description: Text("\"You should talk to this person\": they arrive from imports and agents, and soon from a voice note."))
            } else {
                List(crm.introductions.sorted { $0.changed.at > $1.changed.at }) { intro in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(intro.between.map(name).joined(separator: " ↔ ")).font(.headline)
                        Text(intro.why.value)
                        Text("Suggested by \(crm.people.first { $0.id == intro.suggestedBy.value }?.name.value ?? intro.suggestedBy.value) · \(intro.status.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Introductions")
    }
}
