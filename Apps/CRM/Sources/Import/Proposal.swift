import Foundation

/// A contact the import offers, for a person to accept, change or drop. Nothing is kept until it is
/// accepted; then `ImportPlanner` turns the accepted ones into records for one commit.
struct Proposal: Identifiable, Hashable, Sendable {
    enum Decision: String, Hashable, Sendable {
        case pending, accept, drop
    }

    let id: String
    var candidate: ContactCandidate
    /// An existing person this looks like: accepting it adds to that record instead of making a new one.
    var match: Match?
    var decision: Decision = .pending

    init(id: String = RecordID.make(), candidate: ContactCandidate, match: Match? = nil) {
        self.id = id
        self.candidate = candidate
        self.match = match
    }
}

struct Match: Hashable, Sendable {
    enum Strength: String, Hashable, Sendable {
        /// The same email or phone number.
        case same
        /// The same name, nothing else in common.
        case likely
    }

    var personID: String
    var name: String
    var strength: Strength
    var reasons: [String]
}

enum ProposalMaker {
    /// One proposal per contact: candidates that share an email or a phone within the import are
    /// joined first, then each is matched against the people already in the CRM.
    static func make(_ candidates: [ContactCandidate], people: [Person]) -> [Proposal] {
        joined(candidates).map { Proposal(candidate: $0, match: match($0, in: people)) }
    }

    static func joined(_ candidates: [ContactCandidate]) -> [ContactCandidate] {
        var out: [ContactCandidate] = []
        for c in candidates where c.isUsable {
            if let i = out.firstIndex(where: { sharesContact($0, c) }) {
                out[i] = merged(out[i], c)
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func sharesContact(_ a: ContactCandidate, _ b: ContactCandidate) -> Bool {
        let ae = Set(a.emails.map(ContactKeys.email)), be = Set(b.emails.map(ContactKeys.email))
        if !ae.isDisjoint(with: be) { return true }
        let ap = Set(a.phones.map(ContactKeys.phone).filter { $0.count >= 7 })
        let bp = Set(b.phones.map(ContactKeys.phone).filter { $0.count >= 7 })
        return !ap.isDisjoint(with: bp)
    }

    static func merged(_ a: ContactCandidate, _ b: ContactCandidate) -> ContactCandidate {
        var m = a
        if m.name.count < b.name.count && ContactKeys.name(b.name).contains(ContactKeys.name(m.name)) { m.name = b.name }
        m.emails = unique(a.emails + b.emails, by: ContactKeys.email)
        m.phones = unique(a.phones + b.phones, by: ContactKeys.phone)
        m.organisation = a.organisation ?? b.organisation
        m.role = a.role ?? b.role
        m.links = unique(a.links + b.links, by: { $0.lowercased() })
        m.notes = unique(a.notes + b.notes, by: { $0 })
        if a.source.from != b.source.from { m.source.note = [a.source.note, "also in \(b.source.from)"].compactMap { $0 }.joined(separator: "; ") }
        return m
    }

    static func match(_ c: ContactCandidate, in people: [Person]) -> Match? {
        let emails = Set(c.emails.map(ContactKeys.email))
        let phones = Set(c.phones.map(ContactKeys.phone).filter { $0.count >= 7 })
        let name = ContactKeys.name(c.name)
        var likely: Match?
        for p in people {
            var reasons: [String] = []
            if let e = p.emails.map(\.value).first(where: { emails.contains(ContactKeys.email($0)) }) { reasons.append("the same email, \(e)") }
            if let t = p.phones.map(\.value).first(where: { phones.contains(ContactKeys.phone($0)) }) { reasons.append("the same phone, \(t)") }
            if !reasons.isEmpty { return Match(personID: p.id, name: p.name.value, strength: .same, reasons: reasons) }
            if likely == nil, !name.isEmpty, ContactKeys.name(p.name.value) == name {
                likely = Match(personID: p.id, name: p.name.value, strength: .likely, reasons: ["the same name"])
            }
        }
        return likely
    }

    static func unique(_ values: [String], by key: (String) -> String) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(key($0)).inserted }
    }
}
