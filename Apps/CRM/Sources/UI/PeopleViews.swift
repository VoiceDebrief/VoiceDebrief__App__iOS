import SwiftUI

/// The people in the CRM vault, from its records.
struct PeopleList: View {
    let crm: CRMVault
    @State private var search = ""

    private var shown: [Person] {
        guard !search.isEmpty else { return crm.people }
        let key = ContactKeys.name(search)
        return crm.people.filter {
            ContactKeys.name($0.name.value).contains(key) || $0.emails.contains { $0.value.lowercased().contains(search.lowercased()) }
        }
    }

    var body: some View {
        Group {
            if crm.people.isEmpty {
                ContentUnavailableView("No people yet", systemImage: "person.2",
                                       description: Text("Bring contacts in with Import."))
            } else {
                List(shown) { person in
                    NavigationLink {
                        PersonDetail(person: person, crm: crm)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(person.name.value)
                            if let org = crm.organisationName(person.organisation?.value) {
                                Text(org).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .searchable(text: $search)
            }
        }
        .navigationTitle("People")
    }
}

struct PersonSummary: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.name.value).font(.headline)
            if let role = person.role?.value { Text(role) }
            ForEach(person.emails, id: \.self) { Text($0.value).font(.footnote) }
            ForEach(person.phones, id: \.self) { Text($0.value).font(.footnote) }
        }
    }
}

/// One person, each value with where it came from.
struct PersonDetail: View {
    let person: Person
    let crm: CRMVault

    var body: some View {
        List {
            Section("Name") { SourcedRow(value: person.name, fallback: person.source) }
            if let role = person.role { Section("Role") { SourcedRow(value: role, fallback: person.source) } }
            if let org = person.organisation {
                Section("Organisation") {
                    SourcedRow(value: Sourced(crm.organisationName(org.value) ?? org.value, source: org.source), fallback: person.source)
                }
            }
            if !person.emails.isEmpty { Section("Email") { ForEach(person.emails, id: \.self) { SourcedRow(value: $0, fallback: person.source) } } }
            if !person.phones.isEmpty { Section("Phone") { ForEach(person.phones, id: \.self) { SourcedRow(value: $0, fallback: person.source) } } }
            if !person.links.isEmpty { Section("Links") { ForEach(person.links, id: \.self) { SourcedRow(value: $0, fallback: person.source) } } }
            if !person.notes.isEmpty { Section("Notes") { ForEach(person.notes, id: \.self) { SourcedRow(value: $0, fallback: person.source) } } }
            Section("Record") {
                LabeledContent("Made", value: "\(person.created.by.name), \(person.created.at.formatted(date: .abbreviated, time: .shortened))")
                LabeledContent("Changed", value: "\(person.changed.by.name), \(person.changed.at.formatted(date: .abbreviated, time: .shortened))")
                if let key = person.changed.by.key { LabeledContent("Key", value: key).font(.footnote.monospaced()) }
            }
        }
        .navigationTitle(person.name.value)
    }
}

struct SourcedRow: View {
    let value: Sourced<String>
    let fallback: Source

    var body: some View {
        let source = value.source ?? fallback
        VStack(alignment: .leading, spacing: 2) {
            Text(value.value).textSelection(.enabled)
            Text("\(source.saidBy), \(source.from)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct OrganisationsList: View {
    let crm: CRMVault

    var body: some View {
        Group {
            if crm.organisations.isEmpty {
                ContentUnavailableView("No organisations yet", systemImage: "building.2",
                                       description: Text("They are made from the people you import."))
            } else {
                List(crm.organisations) { org in
                    let members = crm.people.filter { $0.organisation?.value == org.id }
                    DisclosureGroup {
                        ForEach(members) { Text($0.name.value) }
                    } label: {
                        LabeledContent(org.name.value, value: "\(members.count)")
                    }
                }
            }
        }
        .navigationTitle("Organisations")
    }
}

extension CRMVault {
    func organisationName(_ id: String?) -> String? {
        guard let id else { return nil }
        return organisations.first { $0.id == id }?.name.value
    }
}
