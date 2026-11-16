import Foundation

/// Invented people, organisations, follow-ups, introductions, interactions and a draft in the
/// `sgit.ai/crm/v1` format, for "Try with sample data", so the CRM can be shown before real records can be
/// read. Every person is invented: example.org and example.com addresses, Ofcom's drama telephone numbers.
/// Kept in a sample vault of its own, never mixed with the real one.
enum SampleData {
    static let event = "Web Summit 2026 (sample)"

    struct Seed {
        let name, email, phone, org, role, met, step: String
        let dueInDays: Int?
        let status: FollowUp.Status
        let waitingOn: String?
        let stage: String
    }

    static let seeds: [Seed] = [
        Seed(name: "Ana Exemplo", email: "ana@example.org", phone: "+44 20 7946 0101", org: "Example Labs", role: "CTO", met: "Day 1, at our stand", step: "Send the deck and a link to the demo vault", dueInDays: -2, status: .open, waitingOn: nil, stage: "to follow up"),
        Seed(name: "Tom Sample", email: "tom@example.com", phone: "+44 20 7946 0102", org: "Sample Ventures", role: "Partner", met: "Investor lounge, day 2", step: "Book a call about the seed round", dueInDays: 0, status: .open, waitingOn: nil, stage: "in conversation"),
        Seed(name: "Rita Demo", email: "rita@example.org", phone: "+44 20 7946 0103", org: "Demo Health", role: "Head of Product", met: "Health stage, after the panel", step: "Share the security review template", dueInDays: 2, status: .open, waitingOn: nil, stage: "to follow up"),
        Seed(name: "Joe Placeholder", email: "joe@example.com", phone: "+44 20 7946 0104", org: "Placeholder Systems", role: "Founder", met: "Night summit, day 1", step: "Wait for their pilot dates", dueInDays: 5, status: .waiting, waitingOn: "Joe", stage: "call booked"),
        Seed(name: "Mia Fictional", email: "mia@example.org", phone: "+44 20 7946 0105", org: "Example Labs", role: "Head of Partnerships", met: "Day 1, at our stand", step: "Introduce her to Rita", dueInDays: 1, status: .open, waitingOn: nil, stage: "to contact"),
        Seed(name: "Leo Invented", email: "leo@example.com", phone: "+44 20 7946 0106", org: "Invented Capital", role: "Associate", met: "Pitch area, day 3", step: "Send the one-page summary", dueInDays: 12, status: .open, waitingOn: nil, stage: "to follow up"),
        Seed(name: "Zoe Specimen", email: "zoe@example.org", phone: "+44 20 7946 0107", org: "Specimen Media", role: "Editor", met: "Media village, day 2", step: "Answer her questions for the article", dueInDays: nil, status: .open, waitingOn: nil, stage: "proposal"),
        Seed(name: "Ian Mock", email: "ian@example.com", phone: "+44 20 7946 0108", org: "Mock Retail", role: "Innovation Lead", met: "Retail stage, day 3", step: "Thank him; not a fit this year", dueInDays: -5, status: .dropped, waitingOn: nil, stage: "parked"),
    ]

    /// All the records, made now, by the person using the app.
    static func records(now rawNow: Date, by actor: Actor, calendar: Calendar = .current) -> [AnyRecord] {
        let now = rawNow.toTheSecond
        let metAt = calendar.date(byAdding: .day, value: -6, to: now)!.toTheSecond
        let stamp = Stamp(at: now, by: actor)
        func source(_ from: String) -> Source {
            Source(saidBy: "Sample data in SGit CRM (invented)", at: metAt, from: from)
        }

        var records: [AnyRecord] = []
        var orgIDs: [String: String] = [:]
        for name in Set(seeds.map(\.org)).sorted() {
            let org = Organisation(id: RecordID.make(), created: stamp, changed: stamp, source: source(event),
                                   name: Sourced(name), website: Sourced("https://\(name.lowercased().replacingOccurrences(of: " ", with: "-")).example.org"),
                                   tags: ["sample"])
            orgIDs[name] = org.id
            records.append(.organisation(org))
        }

        var personIDs: [String: String] = [:]
        for s in seeds {
            let src = source("\(event), \(s.met)")
            let person = Person(id: RecordID.make(), created: stamp, changed: stamp, source: src,
                                name: Sourced(s.name), emails: [Sourced(s.email)], phones: [Sourced(s.phone)],
                                organisation: orgIDs[s.org].map { Sourced($0) }, role: Sourced(s.role),
                                notes: [Sourced("Met: \(s.met)")], tags: ["sample", "web-summit-2026"])
            personIDs[s.name] = person.id
            records.append(.person(person))
            records.append(.interaction(Interaction(id: RecordID.make(), created: stamp, changed: stamp, source: src,
                                                    at: metAt, channel: .meeting, people: [person.id],
                                                    summary: "Met at \(event): \(s.met)", place: "Lisbon (sample)")))
            records.append(.followUp(FollowUp(id: RecordID.make(), created: stamp, changed: stamp, source: src,
                                              person: person.id, owner: actor.name, nextStep: s.step,
                                              due: s.dueInDays.flatMap { calendar.date(byAdding: .day, value: $0, to: now)?.toTheSecond },
                                              status: s.status, waitingOn: s.waitingOn, stage: s.stage)))
        }

        // Two introductions: one suggested at the stand, one already made.
        let suggested = Introduction(id: RecordID.make(), created: stamp, changed: stamp, source: source("\(event), our stand"),
                                     suggestedBy: Sourced(personIDs["Mia Fictional"]!),
                                     between: [personIDs["Mia Fictional"]!, personIDs["Rita Demo"]!],
                                     why: Sourced("Both are working on partnerships in health"), status: .suggested)
        let madeIn = Interaction(id: RecordID.make(), created: stamp, changed: stamp, source: source("\(event), investor lounge"),
                                 at: metAt, channel: .email, people: [personIDs["Tom Sample"]!, personIDs["Leo Invented"]!],
                                 summary: "Introduced Tom and Leo by email")
        let made = Introduction(id: RecordID.make(), created: stamp, changed: stamp, source: source("\(event), investor lounge"),
                                suggestedBy: Sourced("A speaker on the investor panel (invented)"),
                                between: [personIDs["Tom Sample"]!, personIDs["Leo Invented"]!],
                                why: Sourced("Co-investing at seed in the same sector"), status: .made, madeIn: madeIn.id)
        records += [.introduction(suggested), .interaction(madeIn), .introduction(made)]

        // A draft written for the overdue follow-up, for a person to read and send.
        if let ana = records.compactMap({ if case .person(let p) = $0, p.name.value == "Ana Exemplo" { return p } else { return nil } }).first,
           let follow = records.compactMap({ if case .followUp(let f) = $0, f.person == ana.id { return f } else { return nil } }).first {
            records.append(.draft(DraftLog.draft(for: follow, person: ana, channel: .email, by: actor, at: now)))
        }
        return records
    }
}

extension SampleData {
    /// Invented files as an import would find them in a vault: a vCard, a connections export and a contact
    /// in the team CRM's layout, with one person in two of them, to show joining and matching.
    static var importFiles: [(path: String, data: Data)] {
        let vcf = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Nora Example
        ORG:Example Robotics
        TITLE:COO
        EMAIL:nora@example.org
        TEL:+44 20 7946 0201
        NOTE:Met at the robotics stage (sample)
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:Ana Exemplo
        EMAIL:ana@example.org
        TEL:+44 20 7946 0999
        END:VCARD
        """
        let csv = "Name,Company,Job Title,Email,Industry,Location (Country),Connected At,Request Message\n"
            + "Nora Example,Example Robotics,COO,nora@example.org,Robotics,Portugal,2026-11-12,\"Great to meet you (sample)\"\n"
            + "Sam Imaginary,Imaginary Foods,CEO,sam@example.com,Food,Spain,2026-11-13,\n"
        let contact = #"{"id":"kai-sample","type":"contact","name":"Kai Sample","company":"Sample Ventures","role":"Analyst","email":"kai@example.com","pipeline":{"stage":"to follow up","next":"Send the market map"},"updated_at":"2026-11-14T10:00:00Z","updated_by":"agent.sample"}"#
        return [("summit/contacts.vcf", Data(vcf.utf8)),
                ("connections/Web_Summit_2026_Connections.csv", Data(csv.utf8)),
                ("contacts/kai-sample/contact.json", Data(contact.utf8))]
    }
}

extension SampleData {
    /// An invented mailbox in the email cell's twin format (as the email cell confirmed it, 16 November 2026:
    /// a `schema` field on every file, the correspondents under a `correspondents` key): four correspondents, one of whom is owed a
    /// reply, one who only receives, and a sender whose mail never passed DMARC (left out by policy).
    static var twinFiles: [(path: String, data: Data)] {
        func json(_ o: Any) -> Data { (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data() }
        func person(_ name: String, _ address: String) -> [String: Any] { ["name": name, "address": address] }
        let me = person("Owner (sample)", "owner@example.org")
        let ana = person("Ana Exemplo", "ana@example.org")
        let tom = person("Tom Sample", "tom@example.com")
        let rita = person("Rita Demo", "rita@example.org")
        let spam = person("Prize Desk", "prizes@example.net")
        func message(_ id: String, _ thread: String, _ from: [String: Any], _ to: [[String: Any]], _ date: String, _ inbound: Bool, _ subject: String) -> (String, Data) {
            var o: [String: Any] = ["schema": "twin.message/1", "id": id, "thread": thread, "from": from, "to": to, "cc": [], "bcc": [],
                                    "date": date, "direction": inbound ? "inbound" : "outbound", "subject": subject, "labels": [],
                                    "headers": ["message_id": "<\(id)@example.org>", "in_reply_to": NSNull(), "references": []],
                                    "body": ["text": "(sample)", "html": NSNull()], "attachments": [], "language": "en"]
            if inbound { o["auth"] = ["spf": "pass", "dkim": "pass", "dmarc": from["address"] as? String == "prizes@example.net" ? "fail" : "pass"] }
            return ("raw/messages/2026/11/\(id).json", json(o))
        }
        let msgs = [
            message("m-1", "t-1", me, [ana], "2026-11-12T09:00:00Z", false, "Good to meet you at the summit"),
            message("m-2", "t-1", ana, [me], "2026-11-14T16:20:00Z", true, "Re: Good to meet you at the summit"),
            message("m-3", "t-2", tom, [me], "2026-11-13T11:00:00Z", true, "Seed round timing"),
            message("m-4", "t-2", me, [tom], "2026-11-13T15:30:00Z", false, "Re: Seed round timing"),
            message("m-5", "t-3", me, [rita], "2026-11-15T10:00:00Z", false, "The security review template"),
            message("m-6", "t-4", spam, [me], "2026-11-15T08:00:00Z", true, "You have won"),
        ]
        func thread(_ id: String, _ subject: String, _ ids: [String], _ parts: [String], _ last: String) -> (String, Data) {
            ("threads/\(id).json", json(["schema": "twin.thread/1", "id": id, "subject": subject, "messages": ids,
                                         "participants": parts, "labels": [], "last_date": last]))
        }
        let threads = [
            thread("t-1", "Good to meet you at the summit", ["m-1", "m-2"], ["owner@example.org", "ana@example.org"], "2026-11-14T16:20:00Z"),
            thread("t-2", "Seed round timing", ["m-3", "m-4"], ["tom@example.com", "owner@example.org"], "2026-11-13T15:30:00Z"),
            thread("t-3", "The security review template", ["m-5"], ["owner@example.org", "rita@example.org"], "2026-11-15T10:00:00Z"),
            thread("t-4", "You have won", ["m-6"], ["prizes@example.net", "owner@example.org"], "2026-11-15T08:00:00Z"),
        ]
        let correspondents: [String: Any] = [
            "ana@example.org": ["inbound": 1, "outbound": 1, "inbound_verified": 1, "first_seen": "2026-11-12T09:00:00Z"],
            "tom@example.com": ["inbound": 1, "outbound": 1, "inbound_verified": 1, "first_seen": "2026-11-13T11:00:00Z"],
            "rita@example.org": ["inbound": 0, "outbound": 1, "inbound_verified": 0, "first_seen": "2026-11-15T10:00:00Z"],
            "prizes@example.net": ["inbound": 1, "outbound": 0, "inbound_verified": 0, "first_seen": "2026-11-15T08:00:00Z"],
        ]
        var files: [(path: String, data: Data)] = [
            ("mailbox.json", json(["schema": "twin.mailbox/1", "address": "owner@example.org", "name": "Owner (sample)", "simulated": true,
                                   "sync": ["cursor": "1", "synced_at": "2026-11-16T12:00:00Z"]])),
            ("labels.json", json(["schema": "twin.labels/1", "labels": []])),
            ("index/correspondents.json", json(["schema": "twin.correspondents/1", "mailbox": "owner@example.org", "correspondents": correspondents])),
        ]
        files += msgs.map { (path: $0.0, data: $0.1) }
        files += threads.map { (path: $0.0, data: $0.1) }
        return files
    }
}
