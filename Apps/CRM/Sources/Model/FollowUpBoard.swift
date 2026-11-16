import Foundation

/// Who needs what (W3, step 4): every follow-up in a bucket by its status and date, for one owner or all.
/// Plain code over the records; nothing is written.
enum FollowUpBoard {
    enum Bucket: String, CaseIterable, Identifiable, Sendable {
        case overdue, today, thisWeek, later, noDate, waiting, closed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .today: return "Due today"
            case .thisWeek: return "In the next seven days"
            case .later: return "Later"
            case .noDate: return "No date"
            case .waiting: return "Waiting on someone else"
            case .closed: return "Done or dropped"
            }
        }
    }

    struct Item: Identifiable, Hashable, Sendable {
        var followUp: FollowUp
        var personName: String
        var organisation: String?
        var bucket: Bucket
        var id: String { followUp.id }
    }

    static func bucket(_ f: FollowUp, now: Date, calendar: Calendar) -> Bucket {
        switch f.status {
        case .done, .dropped: return .closed
        case .waiting: return .waiting
        case .open: break
        }
        guard let due = f.due else { return .noDate }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        if day < today { return .overdue }
        if day == today { return .today }
        if let week = calendar.date(byAdding: .day, value: 7, to: today), day <= week { return .thisWeek }
        return .later
    }

    /// The owners named on follow-ups, for the filter.
    static func owners(_ followUps: [FollowUp]) -> [String] {
        Array(Set(followUps.map(\.owner))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func items(_ followUps: [FollowUp], people: [Person], organisations: [Organisation],
                      owner: String?, now: Date, calendar: Calendar = .current) -> [Bucket: [Item]] {
        let names = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let orgNames = Dictionary(uniqueKeysWithValues: organisations.map { ($0.id, $0.name.value) })
        var out: [Bucket: [Item]] = [:]
        for f in followUps where owner == nil || f.owner == owner {
            let person = names[f.person]
            let item = Item(followUp: f, personName: person?.name.value ?? "Someone not in the CRM",
                            organisation: person?.organisation.flatMap { orgNames[$0.value] },
                            bucket: bucket(f, now: now, calendar: calendar))
            out[item.bucket, default: []].append(item)
        }
        for key in out.keys {
            out[key]?.sort { ($0.followUp.due ?? .distantFuture, $0.personName) < ($1.followUp.due ?? .distantFuture, $1.personName) }
        }
        return out
    }

    /// A follow-up changed by a person: a new status, step, date or who it waits on, stamped by them.
    static func changed(_ f: FollowUp, status: FollowUp.Status, nextStep: String, due: Date?, waitingOn: String?,
                        by actor: Actor, at: Date) -> FollowUp {
        var next = f
        next.status = status
        next.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        next.due = due?.toTheSecond
        next.waitingOn = status == .waiting ? waitingOn?.trimmingCharacters(in: .whitespaces) : nil
        next.changed = Stamp(at: max(at.toTheSecond, f.created.at), by: actor)
        return next
    }
}
