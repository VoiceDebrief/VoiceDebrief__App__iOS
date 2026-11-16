import Foundation

/// Drafts, never sends (W4 and W5, step 5). A draft is written here or by an agent; a person edits it and
/// sends it from the system's Mail or Messages sheet; only then is it marked sent, with an interaction
/// that logs it. Nothing in this file, or anywhere in the app, sends a message.
enum DraftLog {
    enum Problem: LocalizedError, Equatable {
        case notAPerson, nobodyToWrite, alreadySent

        var errorDescription: String? {
            switch self {
            case .notAPerson: return "Only a person marks a draft sent."
            case .nobodyToWrite: return "The draft is to nobody in the CRM."
            case .alreadySent: return "This draft was already sent."
            }
        }
    }

    /// A first draft for a follow-up, from a plain template (a code cell): a greeting, the next step, a sign-off.
    static func draft(for followUp: FollowUp, person: Person, channel: Draft.Channel, by actor: Actor, at rawDate: Date) -> Draft {
        let at = rawDate.toTheSecond
        let first = person.name.value.split(separator: " ").first.map(String.init) ?? person.name.value
        let signOff = actor.name.isEmpty || actor.name == "Me" ? "" : "\n\n\(actor.name)"
        let body: String
        switch channel {
        case .email: body = "Hello \(first),\n\nIt was good to meet you. \(followUp.nextStep).\(signOff)"
        case .message: body = "Hello \(first), good to meet you. \(followUp.nextStep)."
        }
        let stamp = Stamp(at: at, by: actor)
        return Draft(id: RecordID.make(), created: stamp, changed: stamp,
                     source: Source(saidBy: "A template in SGit CRM", at: at, from: "the follow-up \(followUp.id)"),
                     to: [person.id], channel: channel,
                     subject: channel == .email ? "Good to meet you" : nil, body: body, status: .draft)
    }

    /// After the person sent it from the system's sheet: the draft marked sent and the interaction that logs it.
    static func sent(_ draft: Draft, by actor: Actor, at rawDate: Date) throws -> (draft: Draft, interaction: Interaction) {
        guard actor.kind == .person else { throw Problem.notAPerson }
        guard !draft.to.isEmpty else { throw Problem.nobodyToWrite }
        guard draft.status != .sent else { throw Problem.alreadySent }
        let at = max(rawDate.toTheSecond, draft.created.at)
        let stamp = Stamp(at: at, by: actor)
        let summary = draft.subject.map { "Sent: \($0)" }
            ?? "Sent: " + (draft.body.split(separator: "\n").first.map(String.init) ?? "a message")
        let interaction = Interaction(id: RecordID.make(), created: stamp, changed: stamp,
                                      source: Source(saidBy: actor.name, at: at, from: draft.channel == .email ? "Mail, from SGit CRM" : "Messages, from SGit CRM"),
                                      at: at, channel: draft.channel == .email ? .email : .message,
                                      people: draft.to, summary: summary, draft: draft.id)
        var done = draft
        done.status = .sent
        done.sentAs = interaction.id
        done.changed = stamp
        return (done, interaction)
    }

    /// The addresses to put in the compose sheet, from the people the draft is to.
    static func recipients(_ draft: Draft, people: [Person]) -> [String] {
        draft.to.compactMap { id in
            let person = people.first { $0.id == id }
            return draft.channel == .email ? person?.emails.first?.value : person?.phones.first?.value
        }
    }
}
