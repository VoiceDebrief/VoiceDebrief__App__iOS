import Foundation

/// The places in the app, as the sidebar (iPad) or the list (iPhone) shows them.
///
/// Reality discipline: a section that is not built says so on its own screen, with the step of the
/// brief (`cells/crm-ios/brief.md`) that builds it. A test checks that nothing claims more than this.
enum CRMSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case followUps
    case people
    case organisations
    case introductions
    case drafts
    case importing
    case workflows
    case labs
    case keys
    case agents
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followUps: return "Follow-ups"
        case .people: return "People"
        case .organisations: return "Organisations"
        case .introductions: return "Introductions"
        case .drafts: return "Drafts"
        case .importing: return "Import"
        case .workflows: return "Workflows"
        case .labs: return "Vault apps"
        case .keys: return "Cards and keys"
        case .agents: return "Agents"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .followUps: return "checklist"
        case .people: return "person.2"
        case .organisations: return "building.2"
        case .introductions: return "arrow.left.arrow.right"
        case .drafts: return "square.and.pencil"
        case .importing: return "tray.and.arrow.down"
        case .workflows: return "point.3.connected.trianglepath.dotted"
        case .labs: return "flask"
        case .keys: return "qrcode"
        case .agents: return "person.3.sequence"
        case .about: return "info.circle"
        }
    }

    /// What the section is for, in one plain sentence.
    var purpose: String {
        switch self {
        case .followUps: return "Who needs what from you: what is due, overdue, and waiting on someone else."
        case .people: return "Everyone you met, each value with where it came from."
        case .organisations: return "The companies and teams those people belong to."
        case .introductions: return "People who should talk to each other: who suggested it, between whom, why, and whether it happened."
        case .drafts: return "Messages drafted for you. You edit them and send them yourself; the app never sends."
        case .importing: return "Bring contacts in from a vault, as proposals you review before anything is kept."
        case .workflows: return "What the CRM is made of: workflows, each made of cells, and which are built."
        case .labs: return "Vaults whose own apps run here: features to try before they are built in, switched on per section."
        case .keys: return "Your contact card as a QR code, and the cards of people you met: their keys, checked face to face."
        case .agents: return "What the agents working for you are doing: who is busy, who waits, what they say, and what waits on you."
        case .about: return "What this build is and what it does."
        }
    }

    /// The step of the brief that builds this section, or nil when it is built.
    var step: Int? {
        switch self {
        case .followUps, .introductions, .drafts, .people, .organisations, .importing, .workflows, .labs, .keys, .agents, .about: return nil
        }
    }

    var isBuilt: Bool { step == nil }

    /// The sections the sidebar lists, in order.
    static let sidebar: [CRMSection] = [.followUps, .people, .organisations, .introductions, .drafts, .importing, .keys, .agents, .workflows, .labs]
}
