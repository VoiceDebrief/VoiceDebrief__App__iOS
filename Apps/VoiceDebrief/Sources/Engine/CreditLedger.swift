import Foundation
import Observation

/// The credit ledger, kept on this device as one JSON file. Later it belongs in the user's vault, so
/// that it follows them between devices: the file is one device's append-only log (see `CreditBook`).
///
/// The file is on the user's own device and nothing checks it: someone who edits it changes their
/// own balance. That is known and said on the credit page of the site. Nothing is unlocked by a
/// balance, so there is nothing behind it to take.
@MainActor
@Observable
final class CreditLedger {
    static let shared = CreditLedger()

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "credit-ledger.json")
    }

    let file: URL
    private(set) var book: CreditBook
    /// Set if the ledger could not be read or written, in words for the credit screen.
    private(set) var problem: String?
    @ObservationIgnored private var chargedThisSession: Set<String> = []

    init(file: URL = CreditLedger.defaultFile, now: Date = Date()) {
        self.file = file
        var opened: CreditBook?
        var trouble: String?
        if let data = try? Data(contentsOf: file) {
            opened = try? CreditBook.decode(data)
            if opened == nil {
                // A ledger that cannot be read is kept beside the new one, never overwritten.
                let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(now.timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: file, to: aside)
                trouble = "The credit ledger on this device could not be read. It has been kept as \(aside.lastPathComponent) and a new one started."
            }
        }
        book = opened ?? CreditBook(at: now)
        problem = trouble
        if opened == nil { write() }
    }

    var balance: Int { book.balance }
    var isBelowZero: Bool { book.balance < 0 }
    /// Newest first, as the credit screen lists them.
    var newestFirst: [CreditEntry] { book.entries.reversed() }

    /// Charges for something the app has just done. Never refuses and never throws: the balance may
    /// go below zero, and the work has already happened.
    func charge(_ action: CreditAction, quantity: Double = 1, noteId: String? = nil) {
        let cost = PriceList.cost(action, quantity: quantity)
        let text = PriceList.words(action, quantity: quantity)
        if book.charge(feature: action.rawValue, text: text, cost: cost, quantity: quantity, noteId: noteId) != nil { write() }
    }

    /// Charges for an action on a note at most once while the app is open: reading the same note
    /// again in the same session is not a second charge (newsroom: once per page per session).
    func chargeOnce(_ action: CreditAction, noteId: String) {
        let key = action.rawValue + ":" + noteId
        guard !chargedThisSession.contains(key) else { return }
        chargedThisSession.insert(key)
        charge(action, noteId: noteId)
    }

    /// True if the credit was added; false if this payment reference was already credited.
    @discardableResult
    func topUp(_ receipt: PaymentReceipt) -> Bool {
        guard book.topUp(receipt.credit, ref: receipt.ref, source: receipt.source) != nil else { return false }
        write()
        return true
    }

    func decline(_ entry: CreditEntry, reason: String) {
        if book.decline(entry.id, reason: reason) != nil { write() }
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.encoded().write(to: file, options: .atomic)
        } catch {
            problem = "The credit ledger could not be written: \(error.localizedDescription)"
        }
    }
}
