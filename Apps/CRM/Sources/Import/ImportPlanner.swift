import Foundation

/// What to add with each new person, chosen on the import screen.
struct ImportOptions: Hashable, Sendable {
    /// Where these people were met, as a note interaction for each ("Web Summit 2026"); nil for none.
    var event: String?
    /// A next step for a follow-up on each new person ("Follow up after Web Summit"); nil for none.
    var followUp: String?
    /// Who on our side owns those follow-ups.
    var owner: String
}

/// Turns accepted proposals into the records one commit writes: new people, additions to people who
/// matched, the organisations they name (found or new), and the interactions and follow-ups asked for.
enum ImportPlanner {
    struct Plan: Sendable {
        var records: [AnyRecord] = []
        var newPeople = 0
        var updatedPeople = 0
        var newOrganisations = 0

        /// The files for the commit: path to bytes. Throws if any record has problems.
        func files() throws -> [String: Data] { try RecordFiles.files(records) }

        var summary: String {
            var parts = ["\(newPeople) new \(newPeople == 1 ? "person" : "people")"]
            if updatedPeople > 0 { parts.append("\(updatedPeople) updated") }
            if newOrganisations > 0 { parts.append("\(newOrganisations) new \(newOrganisations == 1 ? "organisation" : "organisations")") }
            return parts.joined(separator: ", ")
        }
    }

    static func plan(_ proposals: [Proposal], people: [Person], organisations: [Organisation],
                     options: ImportOptions, by actor: Actor, at rawDate: Date) -> Plan {
        let at = rawDate.toTheSecond
        let stamp = Stamp(at: at, by: actor)
        var plan = Plan()
        var orgs = organisations
        var peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        var touched: [String] = []
        var created: [String] = []
        var steps: [String: ContactCandidate] = [:]   // person id to the candidate that named a next step

        func organisationID(_ name: String?, source: Source) -> String? {
            guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let key = ContactKeys.name(name)
            if let found = orgs.first(where: { ContactKeys.name($0.name.value) == key }) { return found.id }
            let org = Organisation(id: RecordID.make(), created: stamp, changed: stamp, source: source, name: Sourced(name))
            orgs.append(org)
            plan.records.append(.organisation(org))
            plan.newOrganisations += 1
            return org.id
        }

        for proposal in proposals where proposal.decision == .accept {
            let c = proposal.candidate
            let src = c.source
            let orgID = organisationID(c.organisation, source: src)
            if let match = proposal.match, var person = peopleByID[match.personID] {
                let before = person
                let emails = Set(person.emails.map { ContactKeys.email($0.value) })
                person.emails += c.emails.filter { !emails.contains(ContactKeys.email($0)) }.map { Sourced($0, source: src) }
                let phones = Set(person.phones.map { ContactKeys.phone($0.value) })
                person.phones += c.phones.filter { !phones.contains(ContactKeys.phone($0)) }.map { Sourced($0, source: src) }
                let links = Set(person.links.map { $0.value.lowercased() })
                person.links += c.links.filter { !links.contains($0.lowercased()) }.map { Sourced($0, source: src) }
                let notes = Set(person.notes.map(\.value))
                person.notes += c.notes.filter { !notes.contains($0) }.map { Sourced($0, source: src) }
                if person.role == nil, let role = c.role { person.role = Sourced(role, source: src) }
                if person.organisation == nil, let orgID { person.organisation = Sourced(orgID, source: src) }
                if person != before {
                    person.changed = stamp
                    peopleByID[person.id] = person
                    if !touched.contains(person.id) { touched.append(person.id) }
                }
            } else {
                let person = Person(id: RecordID.make(), created: stamp, changed: stamp, source: src,
                                    name: Sourced(c.name),
                                    emails: c.emails.map { Sourced($0) }, phones: c.phones.map { Sourced($0) },
                                    organisation: orgID.map { Sourced($0) }, role: c.role.map { Sourced($0) },
                                    links: c.links.map { Sourced($0) }, notes: c.notes.map { Sourced($0) })
                peopleByID[person.id] = person
                created.append(person.id)
                if c.nextStep != nil || c.stage != nil { steps[person.id] = c }
            }
        }

        for id in created {
            guard let person = peopleByID[id] else { continue }
            plan.records.append(.person(person))
            plan.newPeople += 1
            if let event = options.event, !event.isEmpty {
                plan.records.append(.interaction(Interaction(id: RecordID.make(), created: stamp, changed: stamp, source: person.source,
                                                             at: person.source.at, channel: .note, people: [id],
                                                             summary: "Met at \(event)")))
            }
            if let c = steps[id] {
                // The source's own next step and stage win over the batch's.
                plan.records.append(.followUp(FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: person.source,
                                                       person: id, owner: c.owner ?? options.owner,
                                                       nextStep: c.nextStep ?? options.followUp ?? "Follow up",
                                                       due: c.due, status: PipelineStage.status(for: c.stage), stage: c.stage)))
            } else if let step = options.followUp, !step.isEmpty {
                plan.records.append(.followUp(FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: person.source,
                                                       person: id, owner: options.owner, nextStep: step, status: .open)))
            }
        }
        for id in touched {
            if let person = peopleByID[id] { plan.records.append(.person(person)); plan.updatedPeople += 1 }
        }
        return plan
    }
}
