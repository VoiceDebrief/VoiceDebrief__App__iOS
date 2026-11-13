import Foundation

/// Credit, on the pattern of newsroom.sgit.ai's SG Meter: a starting balance that counts down as the
/// app is used, may go below zero, and is topped up by paying. Nothing is ever blocked by it.
///
/// The unit is the micro-credit: one millionth of a pound, always a whole number, so that a charge
/// by the second of audio has no rounding. Newsroom counts in pence and tenths of a penny; the app
/// needs a smaller unit because a second of audio costs less than a tenth of a penny.
enum Credit {
    static let perPound = 1_000_000
    static let perPenny = 10_000
    static let symbol = "£"

    /// What a new ledger starts with. PLACEHOLDER: newsroom's figure and the owner's first word (five
    /// pounds), not yet confirmed for the app.
    static let startingCredit = 5 * perPound

    /// "£4.96", or "£4.962" when the amount is not a whole number of pence, or "-£0.25". Rounded to a
    /// tenth of a penny, as newsroom shows it.
    static func money(_ micro: Int) -> String {
        let tenths = (abs(micro) + 500) / 1_000
        let pounds = tenths / 1_000
        let rest = tenths % 1_000
        let digits = rest % 10 == 0 ? String(format: "%d.%02d", pounds, rest / 10) : String(format: "%d.%03d", pounds, rest)
        return (micro < 0 && tenths > 0 ? "-" : "") + symbol + digits
    }

    /// A price in the words a price list uses: "3p", "0.5p" or "£1.20".
    static func price(_ micro: Int) -> String {
        if micro == 0 { return "free" }
        if micro >= perPound { return money(micro) }
        let tenths = (micro + 500) / 1_000
        return tenths % 10 == 0 ? "\(tenths / 10)p" : "\(tenths / 10).\(tenths % 10)p"
    }
}

/// What the app charges for.
enum CreditAction: String, Codable, CaseIterable, Sendable {
    case transcript
    case debrief
    case cleanPassage
    case saveToVault
    case send
}

/// One line of the price list.
struct Price: Identifiable, Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        /// Charged by the second, at this much a minute.
        case minuteOfAudio
        case each
    }

    let action: CreditAction
    let title: String
    let unit: Unit
    /// Micro-credits for one minute of audio, or for one of the thing.
    let micro: Int
    /// False while the app does not yet charge for this, whatever the figure says.
    let charged: Bool

    var id: String { action.rawValue }

    /// "3p a minute of audio, by the second" or "5p each" or "free".
    var words: String {
        guard micro > 0 else { return "free" }
        switch unit {
        case .minuteOfAudio: return "\(Credit.price(micro)) a minute of audio, by the second"
        case .each: return "\(Credit.price(micro)) each"
        }
    }
}

/// Every price, in one place. EVERY FIGURE HERE IS A PLACEHOLDER: the owner has not set the app's
/// prices. The transcript's is the plan's "a few pence per minute"; the debrief's is what newsroom
/// charges for an article read to the end (5p); a clean passage is newsroom's price for a page (1p).
enum PriceList {
    /// Shown on the credit screen beside the prices for as long as it is true.
    static let arePlaceholders = true

    static let all: [Price] = [
        Price(action: .transcript, title: "A transcript", unit: .minuteOfAudio, micro: 3 * Credit.perPenny, charged: true),
        Price(action: .debrief, title: "A debrief", unit: .each, micro: 5 * Credit.perPenny, charged: true),
        Price(action: .cleanPassage, title: "A clean text, by the passage", unit: .each, micro: 1 * Credit.perPenny, charged: true),
        Price(action: .saveToVault, title: "Saving a note to a vault", unit: .each, micro: 0, charged: false),
        Price(action: .send, title: "Sending a note to a recipient", unit: .each, micro: 0, charged: false),
    ]

    static func price(of action: CreditAction) -> Price? {
        all.first { $0.action == action }
    }

    /// What `quantity` of an action costs: seconds of audio for a transcript, a count for the rest.
    /// A started second of audio is a whole second, and a part of a micro-credit is rounded to the nearest.
    static func cost(_ action: CreditAction, quantity: Double, prices: [Price] = all) -> Int {
        guard let price = prices.first(where: { $0.action == action }), price.charged, price.micro > 0,
              quantity > 0, quantity.isFinite else { return 0 }
        switch price.unit {
        case .minuteOfAudio:
            let seconds = Int(quantity.rounded(.up))
            return (price.micro * seconds + 30) / 60
        case .each:
            return price.micro * Int(quantity.rounded())
        }
    }

    /// What a ledger entry says was done.
    static func words(_ action: CreditAction, quantity: Double) -> String {
        switch action {
        case .transcript:
            let seconds = Int(max(0, quantity).rounded(.up))
            let length = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
            return "Transcript, \(length) of audio"
        case .debrief: return "Debrief"
        case .cleanPassage: return "Clean text, one passage"
        case .saveToVault: return "Saved to a vault"
        case .send: return "Sent to a recipient"
        }
    }
}

/// One line of the ledger. Entries are only ever added: a charge that is declined stays, and a
/// refund is written after it.
struct CreditEntry: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case start
        case charge
        case topUp = "topup"
        case refund
    }

    let id: String
    let at: Date
    let kind: Kind
    /// What was done, in words.
    let text: String
    /// Signed: a charge is negative, a top-up, a refund and the starting credit are positive.
    let amount: Int
    /// The balance on this device after this entry.
    let balance: Int
    var action: CreditAction?
    var noteId: String?
    /// Seconds of audio for a transcript, a count for the rest.
    var quantity: Double?
    /// A top-up's payment reference, or the id of the charge a refund gives back.
    var ref: String?
    /// Where a top-up came from: "simulated", or "appstore:" and the App Store's environment.
    var source: String?
    /// Why a charge was declined.
    var reason: String?
}

/// The ledger as a value: one device's append-only log. The file on the device, and later the file
/// in the user's vault, is this and nothing else. Two devices' logs join by taking every entry once,
/// by id; the balance is the sum of the amounts, so it does not depend on the order.
struct CreditBook: Codable, Equatable, Sendable {
    static let version = 1

    /// Why a charge was declined, after newsroom's "Don't charge me" and its reasons.
    static let declineReasons = [
        "The result was not usable",
        "I did not need it",
        "It was a test",
        "Another reason",
    ]

    var v: Int
    /// A random name for this device's log, so that logs can be told apart once they share a vault.
    var device: String
    private(set) var entries: [CreditEntry]

    /// A new ledger, holding the starting credit as its first entry.
    init(device: String = UUID().uuidString, startingCredit: Int = Credit.startingCredit, at: Date = Date()) {
        v = Self.version
        self.device = device
        entries = []
        add(.start, text: "Starting credit", amount: startingCredit, at: at)
    }

    /// The sum of every amount. It may be below zero.
    var balance: Int { entries.reduce(0) { $0 + $1.amount } }

    /// What has been charged and not given back.
    var spent: Int { -entries.filter { $0.kind == .charge || $0.kind == .refund }.reduce(0) { $0 + $1.amount } }

    var toppedUp: Int { entries.filter { $0.kind == .topUp }.reduce(0) { $0 + $1.amount } }

    /// True if every entry's recorded balance is the one before it plus its amount.
    var addsUp: Bool {
        var running = 0
        for entry in entries {
            running += entry.amount
            if entry.balance != running { return false }
        }
        return true
    }

    /// Charges for something that was done. Returns nil, and writes nothing, if it costs nothing.
    @discardableResult
    mutating func charge(_ action: CreditAction, quantity: Double, noteId: String?, at: Date = Date(),
                         prices: [Price] = PriceList.all) -> CreditEntry? {
        let cost = PriceList.cost(action, quantity: quantity, prices: prices)
        guard cost > 0 else { return nil }
        return add(.charge, text: PriceList.words(action, quantity: quantity), amount: -cost, at: at) {
            $0.action = action
            $0.noteId = noteId
            $0.quantity = quantity
        }
    }

    /// Adds credit that was paid for. A payment reference is credited once, as newsroom does it.
    @discardableResult
    mutating func topUp(_ amount: Int, ref: String, source: String, at: Date = Date()) -> CreditEntry? {
        guard amount > 0, !ref.isEmpty, !entries.contains(where: { $0.kind == .topUp && $0.ref == ref }) else { return nil }
        let simulated = source == "simulated"
        return add(.topUp, text: simulated ? "Top-up (simulated, no money taken)" : "Top-up", amount: amount, at: at) {
            $0.ref = ref
            $0.source = source
        }
    }

    func isDeclined(_ entry: CreditEntry) -> Bool {
        entries.contains { $0.kind == .refund && $0.ref == entry.id }
    }

    /// Gives a charge back, with the reason. Once per charge.
    @discardableResult
    mutating func decline(_ entryId: String, reason: String, at: Date = Date()) -> CreditEntry? {
        guard let charge = entries.first(where: { $0.id == entryId }), charge.kind == .charge, !isDeclined(charge) else { return nil }
        return add(.refund, text: "Declined: \(charge.text)", amount: -charge.amount, at: at) {
            $0.action = charge.action
            $0.noteId = charge.noteId
            $0.ref = charge.id
            $0.reason = reason
        }
    }

    @discardableResult
    private mutating func add(_ kind: CreditEntry.Kind, text: String, amount: Int, at: Date,
                              _ fill: (inout CreditEntry) -> Void = { _ in }) -> CreditEntry {
        var entry = CreditEntry(id: UUID().uuidString, at: at, kind: kind, text: text, amount: amount, balance: balance + amount)
        fill(&entry)
        entries.append(entry)
        return entry
    }

    // MARK: The file

    static func decode(_ data: Data) throws -> CreditBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CreditBook.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
