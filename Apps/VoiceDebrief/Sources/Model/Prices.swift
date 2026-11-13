import Foundation

/// What this app charges for. The raw value is the feature's key in the ledger: it is written to the
/// file and added up across devices, so it is never renamed.
enum CreditAction: String, CaseIterable, Sendable {
    case transcript
    case debrief
    case cleanPassage
    case importFile
    case glossaryWord
    case createVault
    case addVault
    case saveToVault
    case send
    case addRecipient
    case pushVault
    case pullVault
    case addServer
}

/// One line of the price list.
struct Price: Identifiable, Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        /// By the minute of audio; a started minute is a whole one.
        case minuteOfAudio
        case each
        /// By the file written.
        case file
    }

    let action: CreditAction
    let title: String
    let unit: Unit
    /// Micro-credits for one minute of audio, or for one of the thing.
    let micro: Int

    var id: String { action.rawValue }

    /// "3p a minute of audio" or "10p each" or "1p a file".
    var words: String {
        switch unit {
        case .minuteOfAudio: return "\(Credit.price(micro)) a minute of audio"
        case .each: return "\(Credit.price(micro)) each"
        case .file: return "\(Credit.price(micro)) a file"
        }
    }
}

/// Every price, in one place. EVERY FIGURE HERE IS A PLACEHOLDER the owner can change. The owner's
/// word (13 November 2026): just about everything the user does costs a little, in steps of one
/// penny for now; creating a vault about 10p, a file saved to a vault about 1p. The transcript's
/// figure is the plan's "a few pence per minute"; the debrief's is what newsroom charges for an
/// article read to the end. Recording is not here and is never charged.
enum PriceList {
    /// Shown on the credit screen beside the prices for as long as it is true.
    static let arePlaceholders = true

    static let all: [Price] = [
        Price(action: .transcript, title: "A transcript", unit: .minuteOfAudio, micro: 3 * Credit.perPenny),
        Price(action: .debrief, title: "A debrief", unit: .each, micro: 5 * Credit.perPenny),
        Price(action: .cleanPassage, title: "A clean text, by the passage", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .importFile, title: "Opening an audio file", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .glossaryWord, title: "Adding one of your words", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .createVault, title: "Creating a vault", unit: .each, micro: 10 * Credit.perPenny),
        Price(action: .addVault, title: "Adding a vault made elsewhere", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .saveToVault, title: "Saving a note to a vault", unit: .file, micro: 1 * Credit.perPenny),
        Price(action: .send, title: "Sending a note to a recipient", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .addRecipient, title: "Adding a recipient", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .pushVault, title: "Pushing a vault to a server", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .pullVault, title: "Pulling a vault from a server", unit: .each, micro: 1 * Credit.perPenny),
        Price(action: .addServer, title: "Adding a server", unit: .each, micro: 1 * Credit.perPenny),
    ]

    static func price(of action: CreditAction) -> Price? {
        all.first { $0.action == action }
    }

    /// A feature's name for a person, from its key in the ledger. A key this build does not know
    /// (written by a later build, or another app) is shown as it is.
    static func title(ofFeature key: String) -> String {
        CreditAction(rawValue: key).flatMap(price(of:))?.title ?? key
    }

    /// What `quantity` of an action costs: seconds of audio for a transcript, a count for the rest.
    static func cost(_ action: CreditAction, quantity: Double, prices: [Price] = all) -> Int {
        guard let price = prices.first(where: { $0.action == action }), price.micro > 0,
              quantity > 0, quantity.isFinite else { return 0 }
        switch price.unit {
        case .minuteOfAudio: return price.micro * Int((quantity / 60).rounded(.up))
        case .each, .file: return price.micro * Int(quantity.rounded())
        }
    }

    /// What a ledger entry says was done.
    static func words(_ action: CreditAction, quantity: Double) -> String {
        let count = Int(quantity.rounded())
        switch action {
        case .transcript:
            let seconds = Int(max(0, quantity).rounded(.up))
            let length = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
            return "Transcript, \(length) of audio"
        case .debrief: return "Debrief"
        case .cleanPassage: return "Clean text, one passage"
        case .importFile: return "Opened an audio file"
        case .glossaryWord: return "Added one of your words"
        case .createVault: return "Created a vault"
        case .addVault: return "Added a vault"
        case .saveToVault: return count == 1 ? "Saved to a vault, 1 file" : "Saved to a vault, \(count) files"
        case .send: return "Sent to a recipient"
        case .addRecipient: return "Added a recipient"
        case .pushVault: return "Pushed a vault to a server"
        case .pullVault: return "Pulled a vault from a server"
        case .addServer: return "Added a server"
        }
    }
}
