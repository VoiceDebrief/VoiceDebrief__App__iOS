import Foundation

struct Person: CRMRecord {
    static let kind = RecordKind.person
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    var name: Sourced<String>
    var emails: [Sourced<String>] = []
    var phones: [Sourced<String>] = []
    /// The organisation record this person belongs to, by id.
    var organisation: Sourced<String>?
    var role: Sourced<String>?
    var links: [Sourced<String>] = []
    var notes: [Sourced<String>] = []
    var tags: [String] = []

    func kindProblems() -> [String] {
        name.value.trimmingCharacters(in: .whitespaces).isEmpty ? ["a person with no name"] : []
    }
}

struct Organisation: CRMRecord {
    static let kind = RecordKind.organisation
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    var name: Sourced<String>
    var website: Sourced<String>?
    var notes: [Sourced<String>] = []
    var tags: [String] = []

    func kindProblems() -> [String] {
        name.value.trimmingCharacters(in: .whitespaces).isEmpty ? ["an organisation with no name"] : []
    }
}

struct Interaction: CRMRecord {
    enum Channel: String, Codable, Sendable {
        case meeting, email, message, call, note, lane
    }

    static let kind = RecordKind.interaction
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    var at: Date
    var channel: Channel
    /// The people records taking part, by id.
    var people: [String]
    var summary: String
    var place: String?
    /// The draft this interaction logs, when it was a sent draft.
    var draft: String?

    func kindProblems() -> [String] {
        people.isEmpty ? ["an interaction with nobody"] : []
    }
}

/// "You should talk to this person": first-class, because for us it is the heart of it.
struct Introduction: CRMRecord {
    enum Status: String, Codable, Sendable {
        case suggested, accepted, made, happened, declined
    }

    static let kind = RecordKind.introduction
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    /// Who suggested it: a person record's id, or a name when they are not a record.
    var suggestedBy: Sourced<String>
    /// The two people records to introduce, by id.
    var between: [String]
    var why: Sourced<String>
    var status: Status
    /// The interaction in which it was made, when it was.
    var madeIn: String?

    enum CodingKeys: String, CodingKey {
        case format, id, created, changed, source, between, why, status
        case suggestedBy = "suggested_by", madeIn = "made_in"
    }

    func kindProblems() -> [String] {
        var found: [String] = []
        if between.count != 2 || Set(between).count != 2 { found.append("an introduction is between two different people") }
        if (status == .made || status == .happened) && madeIn == nil { found.append("an introduction \(status.rawValue) names no interaction") }
        return found
    }
}

struct FollowUp: CRMRecord {
    enum Status: String, Codable, Sendable {
        case open, waiting, done, dropped
    }

    static let kind = RecordKind.followUp
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    /// The person record it is about, by id.
    var person: String
    /// Who on our side owns it.
    var owner: String
    var nextStep: String
    var due: Date?
    var status: Status
    /// Who it is waiting on, when it is waiting.
    var waitingOn: String?
    /// The pipeline stage as text (the team's stages: to contact, to follow up, in conversation, call booked,
    /// proposal, won, parked), kept as the source wrote it.
    var stage: String?

    enum CodingKeys: String, CodingKey {
        case format, id, created, changed, source, person, owner, due, status, stage
        case nextStep = "next_step", waitingOn = "waiting_on"
    }

    func kindProblems() -> [String] {
        var found: [String] = []
        if nextStep.trimmingCharacters(in: .whitespaces).isEmpty { found.append("a follow-up with no next step") }
        if status == .waiting && (waitingOn ?? "").isEmpty { found.append("a follow-up waiting on nobody") }
        return found
    }
}

/// A message prepared for a person to send. The app never sends one itself: a person sends it from
/// the system's compose sheet, and the sent message is logged back as an interaction.
struct Draft: CRMRecord {
    enum Status: String, Codable, Sendable {
        case draft, ready, sent, dropped
    }

    enum Channel: String, Codable, Sendable {
        case email, message
    }

    static let kind = RecordKind.draft
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    /// The people records it is to, by id.
    var to: [String]
    var channel: Channel
    var subject: String?
    var body: String
    var status: Status
    /// The interaction that logs it once a person has sent it.
    var sentAs: String?

    enum CodingKeys: String, CodingKey {
        case format, id, created, changed, source, to, channel, subject, body, status
        case sentAs = "sent_as"
    }

    func kindProblems() -> [String] {
        var found: [String] = []
        if to.isEmpty { found.append("a draft to nobody") }
        if status == .sent && sentAs == nil { found.append("a draft marked sent with no interaction logging it") }
        if status == .sent && changed.by.kind != .person { found.append("a draft marked sent by \(changed.by.name), not a person") }
        return found
    }
}

/// A play: a named sequence of steps the team repeats (after a conference, for an investor).
struct Play: CRMRecord {
    static let kind = RecordKind.play
    var format = CRMFormat.version
    var id: String
    var created: Stamp
    var changed: Stamp
    var source: Source

    var name: String
    var purpose: String
    var steps: [String]

    func kindProblems() -> [String] {
        steps.isEmpty ? ["a play with no steps"] : []
    }
}
