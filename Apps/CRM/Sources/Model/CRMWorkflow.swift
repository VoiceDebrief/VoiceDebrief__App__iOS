import Foundation

/// What the CRM is made of (website/crm/workflows/): cells, joined into workflows, joined into plays.
/// A test holds this list to the reality file: only W1 is built.
struct CellKind: Hashable, Sendable {
    let altitude: String
    let name: String
    let runsIn: String

    static let code = CellKind(altitude: "A0", name: "Code", runsIn: "in the app")
    static let onDevice = CellKind(altitude: "A1", name: "Apple model on the device", runsIn: "in the app; nothing leaves the device")
    static let cloud = CellKind(altitude: "A1", name: "Cloud model", runsIn: "behind a lane; the app holds no API key")
    static let agent = CellKind(altitude: "A2", name: "Agent", runsIn: "a Claude session writing proposals to a lane")
    static let person = CellKind(altitude: "P", name: "Person", runsIn: "in the app")
}

struct Cell: Hashable, Sendable {
    let kind: CellKind
    let job: String
}

struct CRMWorkflow: Identifiable, Hashable, Sendable {
    enum Status: String, Sendable {
        case built = "Built, not yet tried on a device"
        case proposed = "Proposed"
    }

    let id: String
    let title: String
    let trigger: String
    let cells: [Cell]
    let writes: String
    let waitsFor: String
    let status: Status
    /// Where it is in the app, when it is built.
    let section: CRMSection?

    var isBuilt: Bool { status == .built }

    static let all: [CRMWorkflow] = [
        CRMWorkflow(id: "W1", title: "Import contacts from a vault", trigger: "A vault key or QR code; a vault of vaults such as crm-sources",
                    cells: [Cell(kind: .code, job: "Open the vault and list what it holds"),
                            Cell(kind: .code, job: "Read vCards, CSV, JSON lists, CRM records and the team CRM layout"),
                            Cell(kind: .onDevice, job: "Read the text on badge and card photos (Vision)"),
                            Cell(kind: .code, job: "Join duplicates and match people already kept"),
                            Cell(kind: .person, job: "Accept, change or drop each proposal"),
                            Cell(kind: .code, job: "Keep what was accepted in one signed commit")],
                    writes: "People, organisations, interactions, follow-ups", waitsFor: "Every proposal", status: .built, section: .importing),
        CRMWorkflow(id: "W2", title: "Capture at a stand", trigger: "A photo of a badge or card, or ten seconds of voice",
                    cells: [Cell(kind: .onDevice, job: "Read the photo or the words"), Cell(kind: .onDevice, job: "Ask one question: who, where, what next"),
                            Cell(kind: .code, job: "Match people already kept"), Cell(kind: .person, job: "Accept the proposal")],
                    writes: "A person, an interaction, a follow-up", waitsFor: "The proposal", status: .proposed, section: nil),
        CRMWorkflow(id: "W3", title: "Who needs what today", trigger: "Opening the app; a date",
                    cells: [Cell(kind: .code, job: "Due, overdue and waiting, by owner"),
                            Cell(kind: .person, job: "Change a follow-up's status, next step or date")],
                    writes: "A changed follow-up, as a signed commit", waitsFor: "The person, for every change", status: .built, section: .followUps),
        CRMWorkflow(id: "W4", title: "Draft a follow-up in our voice", trigger: "A follow-up that is due",
                    cells: [Cell(kind: .cloud, job: "Draft in our voice"), Cell(kind: .onDevice, job: "Or a short note on the device"),
                            Cell(kind: .person, job: "Edit and send from the Mail or Messages sheet")],
                    writes: "A draft, then an interaction once sent", waitsFor: "Sending, always", status: .proposed, section: nil),
        CRMWorkflow(id: "W5", title: "Log what was sent and what came back", trigger: "The compose sheet closing; a reply shared to the app",
                    cells: [Cell(kind: .person, job: "Send the draft from the system's Mail or Messages sheet"),
                            Cell(kind: .code, job: "Mark the draft sent and log the message as an interaction")],
                    writes: "The draft, sent; an interaction", waitsFor: "The person pressing Send", status: .built, section: .drafts),
        CRMWorkflow(id: "W6", title: "Make an introduction", trigger: "\"You should talk to this person\", typed or said",
                    cells: [Cell(kind: .onDevice, job: "Pull out who, between whom and why"), Cell(kind: .code, job: "Ask each side first"),
                            Cell(kind: .cloud, job: "Draft to each side"), Cell(kind: .person, job: "Send each message")],
                    writes: "An introduction, two drafts", waitsFor: "Asking each side; every email", status: .proposed, section: nil),
        CRMWorkflow(id: "W7", title: "Debrief a meeting by voice", trigger: "A voice note",
                    cells: [Cell(kind: .onDevice, job: "Transcribe (SpeechAnalyzer)"), Cell(kind: .onDevice, job: "One question at a time: who, what, next"),
                            Cell(kind: .code, job: "Match people already kept"), Cell(kind: .person, job: "Accept the proposals")],
                    writes: "An interaction, follow-ups, introductions", waitsFor: "Every proposal", status: .proposed, section: nil),
        CRMWorkflow(id: "W8", title: "Merge duplicates and add sources", trigger: "A new batch; weekly",
                    cells: [Cell(kind: .agent, job: "Propose merges"), Cell(kind: .agent, job: "Enrich from public pages, each value with its source"),
                            Cell(kind: .person, job: "Accept each merge and each value")],
                    writes: "Changes to people and organisations", waitsFor: "Every merge and new value", status: .proposed, section: nil),
        CRMWorkflow(id: "W9", title: "The team's weekly pipeline", trigger: "Monday morning",
                    cells: [Cell(kind: .code, job: "Count by stage and owner"), Cell(kind: .cloud, job: "A short summary"),
                            Cell(kind: .person, job: "Send the digest")],
                    writes: "A digest draft", waitsFor: "Sending the digest", status: .proposed, section: nil),
        CRMWorkflow(id: "W10", title: "Our own fleet as records", trigger: "Messages on our lanes",
                    cells: [Cell(kind: .code, job: "An agent as a person, a team as an organisation, a lane message as an interaction"),
                            Cell(kind: .person, job: "Add an agent the team has not seen")],
                    writes: "People, interactions, introductions", waitsFor: "A new agent", status: .proposed, section: nil),
        CRMWorkflow(id: "W11", title: "What the agents are doing", trigger: "Lanes and the agents vault, while the screen is open",
                    cells: [Cell(kind: .code, job: "Read each agent's status, its messages and what it waits on"),
                            Cell(kind: .code, job: "Draw cells, workflows and who talks to whom"),
                            Cell(kind: .person, job: "See what waits on you (answering it through a lane comes next)")],
                    writes: "Nothing yet: it only reads", waitsFor: "Every decision", status: .built, section: .agents),
        CRMWorkflow(id: "W12", title: "Exchange keys by QR", trigger: "Two people, two phones",
                    cells: [Cell(kind: .code, job: "Show my contact card (my public keys) as a QR code"),
                            Cell(kind: .code, job: "Scan theirs, check its signature"),
                            Cell(kind: .person, job: "Confirm it is them"),
                            Cell(kind: .code, job: "Put their key on their record in the CRM (sealing to it comes next)")],
                    writes: "A person with their key", waitsFor: "Confirming who they are", status: .built, section: .keys),
    ]
}
